import Foundation

@main struct TonicRecallAdmissionTests {
    static func main() throws {
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let store=PerformanceStore();store.setlist=TestFixtures.setlist()
        let good=TestFixtures.padSound()
        let absent=ExternalSound(kind:.samplerPreset,name:"Generated Offline Pad",fileName:"generated-missing-pad.aupreset")
        func state(_ sound:ExternalSound,enabled:Bool)->TonicPatchState {
            TonicPatchState(enabled:enabled,root:8,timbre:2,sound:sound,velocitySelector:false,gain:0.2,brightness:0.3,shimmer:0)
        }
        store.setlist.patches[1].tonicState=state(absent,enabled:true)
        try store.audio.prepareOffline();store.start();defer{store.stopAudio()}
        for i in store.patch.layers.indices {store.setGain(i,0)}
        store.setTonicInstrument(good);store.toggleTonic(3)
        assert(store.tonic==3 && !store.tonicSoundLoading)
        store.captureSnapshot(0);store.save();store.noteOn(60);store.setSustain(true);store.metronome=true
        let id=store.currentSetlistID!,patch=store.patch.id,snapshot=store.activeSnapshot
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        let model=try encoder.encode(store.setlist)
        let primary=root.appendingPathComponent("setlist.json"),settings=root.appendingPathComponent("settings.json")
        let bytes=try Data(contentsOf:primary),preferences=try Data(contentsOf:settings)
        let library=try SetlistLibrary(root:root.appendingPathComponent("Setlists"))
        let sourcePath=library.root.appendingPathComponent(id.uuidString+".json"),sourceBytes=try Data(contentsOf:sourcePath)
        let unit=store.audio.externalRack!.unit(channel:15)!,generation=store.audio.externalRack!.graphGeneration
        func retained(_ reason:String) throws {
            assert(store.patch.id==patch && store.currentSetlistID==id && store.activeSnapshot==snapshot,reason)
            assert(store.tonic==3 && store.tonicSound==good && store.tonicLastRoot==3 && !store.tonicSoundLoading)
            assert(store.started && store.audio.running && !store.audioFailed && store.held.contains(60) && store.sustain && store.metronome)
            assert(store.audio.externalRack!.unit(channel:15) === unit && store.audio.externalRack!.graphGeneration==generation)
            assert(try! encoder.encode(store.setlist)==model)
            assert(try! Data(contentsOf:primary)==bytes)
            assert(try! Data(contentsOf:settings)==preferences)
            assert(try! Data(contentsOf:sourcePath)==sourceBytes)
            store.metronome=false
            var energy=0.0
            for _ in 0..<24 {
                let block=try store.audio.offlineBlock()
                for i in 0..<Int(block.frameLength) {let value=block.floatChannelData![0][i];assert(value.isFinite);energy += Double(value*value)}
            }
            assert(energy>0.001,"The retained pad alone must keep rendering")
            store.metronome=true
        }
        let only=CommandLine.arguments.dropFirst().first
        if only==nil || only=="patch" {
            store.choose(1);try retained("Missing recalled pad must not replace the active patch")
        }
        var candidate=TestFixtures.setlist();candidate.name="Generated Pad Recall"
        let imported=root.appendingPathComponent("generated-pad-setlist.json")
        for enabled in [true,false] {
            candidate.patches[0].tonicState=state(absent,enabled:enabled)
            let saved=try library.save(candidate)
            if only==nil || only=="setlist" {
                store.openLocalSetlist(saved.id);try retained("Missing recalled pad must not replace the active setlist")
            }
            if only==nil || only=="import" {
                try encoder.encode(candidate).write(to:imported)
                let importedBytes=try Data(contentsOf:imported)
                store.load(imported);try retained("Missing recalled pad must not replace the imported performance")
                assert(try! Data(contentsOf:imported)==importedBytes)
            }
        }
        // A readable sampler with unsupported non-looping pad zones is rejected
        // before either the old pad or ordinary held notes are disturbed.
        let rack=store.audio.externalRack!
        let padFile=rack.libraryURL.appendingPathComponent(good.fileName!)
        var plist=try PropertyListSerialization.propertyList(from:Data(contentsOf:padFile),format:nil) as! [String:Any]
        var instrument=plist["Instrument"] as! [String:Any],layers=instrument["Layers"] as! [[String:Any]]
        for i in layers.indices {
            var zones=layers[i]["Zones"] as! [[String:Any]]
            for j in zones.indices {zones[j]["loop enabled"]=false}
            layers[i]["Zones"]=zones
        }
        instrument["Layers"]=layers;plist["Instrument"]=instrument
        var unsupported=good;unsupported.fileName="generated-nonloop-pad.aupreset"
        try PropertyListSerialization.data(fromPropertyList:plist,format:.xml,options:0).write(to:rack.libraryURL.appendingPathComponent(unsupported.fileName!))
        candidate.patches[0].tonicState=state(unsupported,enabled:true)
        let rejected=try library.save(candidate)
        store.openLocalSetlist(rejected.id);try retained("Unsupported recalled pad map must retain the current performance")
        candidate.patches[0].tonicState=state(good,enabled:true)
        let ready=try library.save(candidate);store.openLocalSetlist(ready.id)
        assert(store.currentSetlistID==ready.id && store.tonic==8 && store.started && store.audio.running)
        print("PASS pad recall admission: patch/setlist/import, enabled/bypassed missing sound, unsupported map, retained pad-only audio/state/bytes and valid retry")
    }
}
