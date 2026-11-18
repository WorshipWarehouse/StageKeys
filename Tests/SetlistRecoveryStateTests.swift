import Foundation
import AVFoundation

@main struct SetlistRecoveryStateTests {
    @MainActor static func main() throws {
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let store=PerformanceStore();store.setlist=TestFixtures.setlist()
        try store.audio.prepareOffline();store.start();defer{store.stopAudio()}
        store.captureSnapshot(0);store.captureSnapshot(0)
        assert(store.snapshotUndo != nil)
        store.save()
        let id=store.currentSetlistID!,library=try SetlistLibrary(root:root.appendingPathComponent("Setlists"))
        let primary=library.root.appendingPathComponent(id.uuidString+".json")
        let previous=primary.appendingPathExtension("previous")
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        var missing=store.setlist
        missing.patches[0].layers[0].external=ExternalSound(kind:.sample,name:"Missing",fileName:"missing-recovery.wav")
        missing.patches[0].layers[0].instrument = -1
        let missingBytes=try encoder.encode(missing),before=try Data(contentsOf:primary)
        try missingBytes.write(to:previous,options:.atomic)
        store.noteOn(60)
        let patchID=store.patch.id
        store.recoverPreviousSetlist(id)
        assert(store.patch.id==patchID && store.held.contains(60),"Rejected recovery must retain live intent")
        assert(store.snapshotUndo != nil,"Rejected recovery must retain the active document undo")
        assert((try! Data(contentsOf:primary))==before,"Admission must precede recovery publication")
        store.save() // Settings Done must not erase the still-recoverable source.
        assert((try! Data(contentsOf:previous))==missingBytes)
        store.panic()

        let rack=store.audio.externalRack!
        var replies:[(AVAudioUnit?,Error?)->Void]=[]
        rack.debugInstantiate={_,reply in replies.append(reply)}
        func completeLoad() {
            let expected=rack.debugInstantiationCallbacks+1
            assert(!replies.isEmpty,"Recovery must instantiate even when cached state matches")
            let fresh=AVAudioUnitSampler();fresh.masterGain = -3
            replies.removeFirst()(fresh,nil)
            let deadline=Date().addingTimeInterval(3)
            while rack.debugInstantiationCallbacks<expected && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.005))}
            assert(rack.debugInstantiationCallbacks==expected)
        }
        let identity=ExternalAUIdentity(type:0x61756d75,subtype:0x74657374,manufacturer:0x54657374,name:"Generated Recovery AU")
        var layer=Layer(name:identity.name,instrument:-1,gain:0.2)
        layer.id=store.patch.layers[0].id;layer.external=ExternalSound(kind:.audioUnit,name:identity.name,component:identity)
        store.commitLayer(0,layer);completeLoad()
        weak var initial=rack.unit(channel:0) as? AVAudioUnitSampler
        initial!.masterGain = -7
        store.save()
        let authored=store.setlist
        // Establish matching document/cache state, then change only the live editor.
        store.audio.configure(0,store.patch.layers[0])
        if !replies.isEmpty {completeLoad()}
        weak var current=rack.unit(channel:0) as? AVAudioUnitSampler
        current!.masterGain = -25
        try encoder.encode(authored).write(to:previous,options:.atomic)
        try Data("damaged primary".utf8).write(to:primary,options:.atomic)
        store.save()
        assert((try! Data(contentsOf:primary))==Data("damaged primary".utf8),"Opening/closing the browser must not autosave over a damaged active document")
        assert(store.setlistLibraryIssues.contains{$0.fileID==id && $0.recoverable})
        store.recoverPreviousSetlist(id)
        assert(store.snapshotUndo==nil,"Recovery must invalidate outgoing snapshot Undo even for matching patch identities")
        completeLoad()
        assert(abs((rack.unit(channel:0) as! AVAudioUnitSampler).masterGain+7)<0.01,"Recovered authored state must replace editor-mutated state")
        store.save()
        assert(abs((rack.unit(channel:0) as! AVAudioUnitSampler).masterGain+7)<0.01)
        // Repeating an equal-state configuration must retain the forced load
        // until a current request installs, not consume it at request creation.
        (rack.unit(channel:0) as! AVAudioUnitSampler).masterGain = -29
        store.audio.configure(0,store.patch.layers[0],forceReload:true)
        let supersededReply=replies.removeFirst()
        store.audio.configure(0,store.patch.layers[0])
        supersededReply(AVAudioUnitSampler(),nil)
        RunLoop.current.run(until:Date().addingTimeInterval(0.05))
        completeLoad()
        assert(abs((rack.unit(channel:0) as! AVAudioUnitSampler).masterGain+7)<0.01)
        // Nil state means a fresh default instance, including on a second recall
        // when both the document and installed-state cache already contain nil.
        var defaults=authored;defaults.patches[0].layers[0].pluginState=nil
        for _ in 0..<2 {
            (rack.unit(channel:0) as! AVAudioUnitSampler).masterGain = -33
            try encoder.encode(defaults).write(to:previous,options:.atomic)
            try Data("damaged primary".utf8).write(to:primary,options:.atomic)
            store.recoverPreviousSetlist(id);completeLoad()
            assert(abs((rack.unit(channel:0) as! AVAudioUnitSampler).masterGain+3)<0.01,"Nil recovery state must not retain the edited live unit")
        }
        print("PASS recovery: rejected admission retains bytes/intent; matching and nil AU state force fresh staged loads")
    }
}
