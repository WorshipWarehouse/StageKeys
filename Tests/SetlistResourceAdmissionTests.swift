import Foundation

@main struct SetlistResourceAdmissionTests {
    static func main() throws {
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let store=PerformanceStore();store.setlist=TestFixtures.setlist()
        try store.audio.prepareOffline();store.start();defer{store.stopAudio()}
        store.choose(1);store.updateTempo(94);store.captureSnapshot(0);store.save()
        store.noteOn(60);store.setSustain(true);store.metronome=true
        let id=store.currentSetlistID!,patch=store.patch.id,snapshot=store.activeSnapshot
        let primary=root.appendingPathComponent("setlist.json"),settings=root.appendingPathComponent("settings.json")
        let library=try SetlistLibrary(root:root.appendingPathComponent("Setlists"))
        let originalFile=library.root.appendingPathComponent(id.uuidString+".json")
        let original=try Data(contentsOf:originalFile),saved=try Data(contentsOf:primary),preferences=try Data(contentsOf:settings)
        let unit=store.audio.externalRack!.unit(channel:0)!
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        let model=try encoder.encode(store.setlist)
        func retained(_ reason:String) throws {
            assert(store.currentSetlistID==id && store.patch.id==patch && store.selected==1 && store.activeSnapshot==snapshot, reason)
            assert(store.held.contains(60) && store.sustain && store.metronome && store.performedTempo==94)
            assert(store.started && store.audio.running && !store.audioFailed && !store.patchLoading)
            assert(store.audio.externalRack!.unit(channel:0) === unit)
            assert(try! encoder.encode(store.setlist)==model)
            assert(try! Data(contentsOf:primary)==saved && (try! Data(contentsOf:settings))==preferences)
            assert(try! Data(contentsOf:originalFile)==original)
            assert(store.message != nil)
            store.metronome=false // Isolate the retained instrument from click energy.
            var energy=0.0
            for _ in 0..<12 {
                let block=try store.audio.offlineBlock()
                for i in 0..<Int(block.frameLength) {let v=block.floatChannelData![0][i];assert(v.isFinite);energy += Double(v*v)}
            }
            assert(energy>0.001,"Rejected activation must retain rendering")
            store.metronome=true
        }
        var missing=TestFixtures.setlist();missing.name="Generated Offline Service"
        missing.patches[0].layers[0].external=ExternalSound(kind:.sample,name:"Generated Missing Sample",fileName:"generated-never-present.wav")
        let entry=try library.save(missing),file=root.appendingPathComponent("generated-setlist.json")
        try encoder.encode(missing).write(to:file)
        let source=try Data(contentsOf:file),candidate=try Data(contentsOf:library.root.appendingPathComponent(entry.id.uuidString+".json"))
        if !CommandLine.arguments.contains("import-only") {
            store.openLocalSetlist(entry.id)
            try retained("Opening an unavailable setlist must preserve the active performance")
        }
        store.message=nil;store.load(file)
        try retained("Importing an unavailable setlist must preserve the active performance")
        assert(try! Data(contentsOf:file)==source)
        assert(try! Data(contentsOf:library.root.appendingPathComponent(entry.id.uuidString+".json"))==candidate)
        // A present generated source with rejected admission must be equally safe.
        let ready=try library.save(TestFixtures.setlist())
        store.audio.debugSoundPreparationFailure=NSError(domain:NSOSStatusErrorDomain,code:917)
        store.openLocalSetlist(ready.id);try retained("Injected preparation rejection must not replace the active document")
        store.audio.debugSoundPreparationFailure=nil
        // Missing AU inventory is checked before requests or current-note cleanup.
        var unavailable=TestFixtures.setlist()
        unavailable.patches[0].layers[0].external=ExternalSound(kind:.audioUnit,name:"Generated Missing AU",component:ExternalAUIdentity(type:0x61756d75,subtype:0x7a7a7a7a,manufacturer:0x7a7a7a7a,name:"Generated Missing AU"))
        let missingAU=try library.save(unavailable)
        store.openLocalSetlist(missingAU.id);try retained("Missing AU must leave the current instrument running")
        // Retry the previously refused source after repairing only the disposable
        // candidate. Successful activation still follows the normal Panic policy.
        _ = try library.save(TestFixtures.setlist(),id:entry.id)
        store.message=nil;store.openLocalSetlist(entry.id)
        assert(store.currentSetlistID==entry.id && store.selected==0 && store.activeSnapshot==nil)
        assert(store.held.isEmpty && !store.sustain && !store.metronome && store.started && store.audio.running)
        store.noteOn(64);assert(store.held.contains(64))
        print("PASS setlist admission: missing samples/AUs, injected rejection, document/unit/note/clock/byte retention, rendered audio and repaired-source retry")
    }
}
