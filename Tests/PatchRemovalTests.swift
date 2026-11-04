import Foundation

@main struct PatchRemovalTests {
    static func main() throws {
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let store=PerformanceStore();store.setlist=TestFixtures.setlist()
        let pad=TestFixtures.padSound()
        store.setlist.patches[2].tempo=150;store.setlist.patches[2].tempoLocked=true;store.setlist.patches[2].visualMode=2
        store.setlist.patches[2].tonicState=TonicPatchState(enabled:true,root:8,timbre:2,sound:pad,velocitySelector:false,gain:0.25,brightness:0.4,shimmer:0)
        try store.audio.prepareOffline();store.start();defer{store.stopAudio()}
        store.choose(1);store.updateTempo(90);store.setTonicInstrument(pad);store.toggleTonic(3)
        store.captureSnapshot(0);store.save();store.noteOn(60);store.setSustain(true);store.metronome=true
        let originalID=store.patch.id,successorID=store.setlist.patches[2].id
        let primary=root.appendingPathComponent("setlist.json"),settings=root.appendingPathComponent("settings.json")
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        func reject(_ reason:String) throws {
            store.save()
            let before=try encoder.encode(store.setlist),bytes=try Data(contentsOf:primary),preferences=try Data(contentsOf:settings)
            let snapshot=store.activeSnapshot,unit=store.audio.externalRack!.unit(channel:0)!,padUnit=store.audio.externalRack!.unit(channel:15)!,graph=store.audio.externalRack!.graphGeneration
            store.removePatch()
            assert(store.setlist.patches.count==3 && store.patch.id==originalID && store.selected==1,reason)
            assert(store.activeSnapshot==snapshot && store.held.contains(60) && store.sustain && store.metronome)
            assert(store.tonic==3 && store.tonicSound==pad && store.started && store.audio.running && !store.audioFailed)
            assert(store.audio.externalRack!.unit(channel:0) === unit && store.audio.externalRack!.unit(channel:15) === padUnit && store.audio.externalRack!.graphGeneration==graph)
            assert(try! encoder.encode(store.setlist)==before)
            assert(try! Data(contentsOf:primary)==bytes)
            assert(try! Data(contentsOf:settings)==preferences)
            store.metronome=false
            var energy=0.0
            for _ in 0..<24 {
                let block=try store.audio.offlineBlock()
                for i in 0..<Int(block.frameLength) {let v=block.floatChannelData![0][i];assert(v.isFinite);energy += Double(v*v)}
            }
            assert(energy>0.001,"Rejected deletion must retain actual instrument audio")
            store.metronome=true
        }
        let mode=CommandLine.arguments.dropFirst().first
        if mode==nil {
            store.patchLock=true;try reject("Patch Lock must reject patch removal at the Store boundary");store.patchLock=false
        }
        if mode==nil || mode=="resources" {
            let goodLayer=store.setlist.patches[2].layers[0]
            store.setlist.patches[2].layers[0].external!.fileName="generated-missing-successor.wav"
            try reject("Unavailable successor must not delete the current patch")
            store.setlist.patches[2].layers[0]=goodLayer
            store.setlist.patches[2].tonicState!.sound=ExternalSound(kind:.samplerPreset,name:"Generated Missing Successor Pad",fileName:"generated-missing-successor-pad.aupreset")
            try reject("Unavailable successor pad must not delete the current patch")
            store.setlist.patches[2].tonicState!.sound=pad
        }
        store.removePatch()
        assert(store.setlist.patches.count==2 && store.patch.id==successorID && store.selected==1)
        assert(store.activeSnapshot==nil && store.held.isEmpty && !store.sustain && !store.metronome)
        assert(store.started && store.audio.running && store.liveTempo==90 && store.performedTempo==150)
        if mode != "tempo" {assert(store.tonic==8 && store.tonicSound==pad,"Deletion must recall the successor Tonic Pad")}
        if mode==nil {assert(store.notesMode,"Deletion must recall the successor visual mode")}
        assert(!store.setlist.patches.contains{$0.id==originalID})
        store.panic();for i in store.patch.layers.indices {store.setGain(i,0)}
        store.master=1;store.reverb=0;store.metronomeSettings.level=1;store.metronome=true
        var clicks:[Int]=[],quiet=100000,frame=0
        for _ in 0..<400 {
            let block=try store.audio.offlineBlock()
            for i in 0..<Int(block.frameLength) {
                let value=abs(block.floatChannelData![0][i]);assert(value.isFinite)
                if value>0.02 {if quiet>2000 {clicks.append(frame)};quiet=0} else {quiet += 1}
                frame += 1
            }
        }
        assert(clicks.count>=4)
        for i in 2..<clicks.count {assert(abs(clicks[i]-clicks[i-1]-19200)<=8,"Successor tempo must reach the rendered click after deletion")}
        store.metronome=false;store.save()
        let restarted=PerformanceStore();assert(restarted.patch.id==successorID && restarted.setlist.patches.count==2)
        // Removing the last array position while stopped is a document edit;
        // an unavailable predecessor must not start or configure an instrument.
        store.stopAudio()
        let predecessor=store.setlist.patches[0].id
        store.setlist.patches[0].layers[0].external!.fileName="generated-offline-predecessor.wav"
        let graph=store.audio.externalRack!.graphGeneration
        store.removePatch()
        assert(store.setlist.patches.count==1 && store.selected==0 && store.patch.id==predecessor)
        assert(!store.started && !store.audio.running && !store.audioFailed && store.audio.externalRack!.graphGeneration==graph)
        let last=try encoder.encode(store.setlist);store.removePatch()
        assert(try! encoder.encode(store.setlist)==last)
        print("PASS patch removal: lock, unavailable successor/pad retention, rendered continuity, successor pad/tempo/visual recall, persistence, stopped last-position edit and final-patch guard")
    }
}
