import Foundation

@main struct SetlistActivationTests {
    static func main() throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline(); store.start(); defer { store.stopAudio() }
        store.updateTempo(90); store.save(); store.captureSnapshot(0)
        let original = store.setlist, originalID = store.currentSetlistID, snapshot = store.activeSnapshot
        let primary = root.appendingPathComponent("setlist.json")
        let settings = root.appendingPathComponent("settings.json")
        let bytes = try Data(contentsOf: primary), settingsBytes = try Data(contentsOf: settings)
        var imported = TestFixtures.setlist(); imported.name = "Generated Imported Service"
        imported.patches[0].tempo = 150; imported.patches[0].tempoLocked = true
        imported.patches[0].tonicState = TonicPatchState(enabled:true,root:5,timbre:2,sound:TestFixtures.padSound(),velocitySelector:false,gain:0.25,brightness:0.4,shimmer:0)
        let url = root.appendingPathComponent("generated-import.json")
        try JSONEncoder().encode(imported).write(to:url)
        let source = try Data(contentsOf:url)
        store.noteOn(60); store.setSustain(true); store.patchLock = true
        // The same fileImporter action must honor the performance lock before
        // touching the source or capturing/saving the current performance.
        if !CommandLine.arguments.contains("recall-only") {
            store.load(url)
            assert(store.setlist.patches[0].id == original.patches[0].id, "File import must respect Patch Lock")
            assert(store.currentSetlistID == originalID && store.activeSnapshot == snapshot)
            assert(store.held.contains(60) && store.sustain && store.audio.running)
            assert(try! Data(contentsOf:primary) == bytes)
            assert(try! Data(contentsOf:settings) == settingsBytes)
        }
        store.patchLock = false; store.message = nil; store.load(url)
        assert(store.setlist.name == imported.name && store.patch.id == imported.patches[0].id)
        assert(store.held.isEmpty && !store.sustain && store.activeSnapshot == nil)
        assert(store.currentSetlistID != originalID && store.audio.running)
        assert(store.tonic == 5 && store.tonicLastRoot == 5 && store.tonicTimbre == 2, "File import must recall the patch Tonic Pad state")
        assert(store.tonicSound == imported.patches[0].tonicState!.sound && store.tonicBrightness == 0.4)
        assert(store.performedTempo == 150 && store.liveTempo == 90)
        assert(try! Data(contentsOf:url) == source)
        let library = try SetlistLibrary(root:root.appendingPathComponent("Setlists"))
        assert(try! library.load(id:originalID!).patches[0].id == original.patches[0].id)
        // Measure the actual click rendered through the imported clock context.
        store.panic(); for i in store.patch.layers.indices { store.setGain(i,0) }
        store.master=1; store.reverb=0
        store.metronomeSettings.level=1; store.metronome=true
        func verifyClick(_ tempo:Double) throws {
            var onsets:[Int]=[], quiet=100000, frame=0
            for _ in 0..<400 {
                let block=try store.audio.offlineBlock()
                for i in 0..<Int(block.frameLength) {
                    let value=abs(block.floatChannelData![0][i]); assert(value.isFinite)
                    if value > 0.02 {
                        if quiet > 2000 {onsets.append(frame)}
                        quiet=0
                    } else {quiet += 1}
                    frame += 1
                }
            }
            assert(onsets.count >= 4, "Imported patch click must render")
            // Compare actual beat spacing in the 48 kHz production graph.
            for i in 2..<onsets.count { assert(abs(onsets[i]-onsets[i-1]-Int(48000*60/tempo)) <= 8, "Imported tempo must reach the rendered click clock") }
        }
        try verifyClick(150)
        store.metronome=false
        imported.patches[0].tempoLocked=false
        imported.patches[0].tonicState!.enabled=false
        imported.patches[0].tonicState!.root=8
        try JSONEncoder().encode(imported).write(to:url)
        store.load(url)
        assert(store.performedTempo==90 && store.liveTempo==90 && store.patch.tempo==150)
        assert(store.tonic==nil && store.tonicLastRoot==8, "Disabled pad recall must retain its chosen key")
        for i in store.patch.layers.indices {store.setGain(i,0)}
        store.metronome=true;try verifyClick(90);store.metronome=false
        store.save()
        let restarted=PerformanceStore()
        assert(restarted.patch.id==store.patch.id && restarted.liveTempo==90 && restarted.performedTempo==90)
        assert(restarted.patch.tonicState==imported.patches[0].tonicState)
        let acceptedID=store.currentSetlistID, acceptedPatch=store.patch.id
        let acceptedBytes=try Data(contentsOf:primary)
        let broken=root.appendingPathComponent("broken.json");try Data("generated broken JSON".utf8).write(to:broken)
        store.noteOn(64);store.load(broken)
        assert(store.currentSetlistID==acceptedID && store.patch.id==acceptedPatch && store.held.contains(64))
        assert(try! Data(contentsOf:primary)==acceptedBytes)
        print("PASS file activation: Patch Lock, retained source/session bytes, saved prior setlist, recalled pad, rendered tempo and rejected input continuity")
    }
}
