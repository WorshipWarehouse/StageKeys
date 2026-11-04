import Foundation

@main struct LiveSessionRecoveryTests {
    static func main() throws {
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let primary=root.appendingPathComponent("setlist.json"),previous=RecoverableSessionFile.previous(primary)
        let damaged=Data("generated interrupted primary".utf8)
        try damaged.write(to:primary)
        let store=PerformanceStore();assert(store.sessionRecoveryRequired)
        store.setlist=TestFixtures.setlist();store.setlist.name="Generated Working Session"
        try store.audio.prepareOffline();store.start();defer{store.stopAudio()}
        store.updateTempo(90);store.captureSnapshot(0)
        store.noteOn(60);store.setSustain(true);store.metronome=true
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        let model=try encoder.encode(store.setlist),patch=store.patch.id,snapshot=store.activeSnapshot
        let unit=store.audio.externalRack!.unit(channel:0)!,graph=store.audio.externalRack!.graphGeneration
        var recovered=TestFixtures.setlist();recovered.name="Generated Recovered Session"
        recovered.patches[0].tempo=150;recovered.patches[0].tempoLocked=true
        var missing=recovered
        missing.patches[0].layers[0].external!.fileName="generated-missing-recovery.wav"
        func archives() throws -> [URL] {
            try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.contains(".damaged-")}
        }
        func retained(_ backup:Data) throws {
            assert(store.sessionRecoveryRequired && store.patch.id==patch && store.activeSnapshot==snapshot,"Unavailable recovery must retain the active performance and recovery flag")
            assert(store.started && store.audio.running && !store.audioFailed && store.held.contains(60) && store.sustain && store.metronome)
            assert(store.audio.externalRack!.unit(channel:0) === unit && store.audio.externalRack!.graphGeneration==graph)
            assert(try! encoder.encode(store.setlist)==model)
            assert(try! Data(contentsOf:primary)==damaged)
            assert(try! Data(contentsOf:previous)==backup)
            assert(try! archives().isEmpty,"Rejected recovery must not create a damaged-file archive or publish the backup")
            store.metronome=false
            var energy=0.0
            for _ in 0..<24 {
                let block=try store.audio.offlineBlock()
                for i in 0..<Int(block.frameLength) {let v=block.floatChannelData![0][i];assert(v.isFinite);energy += Double(v*v)}
            }
            assert(energy>0.001,"Rejected recovery must retain actual instrument audio")
            store.metronome=true
        }
        if !CommandLine.arguments.contains("tempo-only") {
            let unavailable=try encoder.encode(missing);try unavailable.write(to:previous)
            store.recoverPreviousSession();try retained(unavailable)
            var missingPad=recovered
            missingPad.patches[0].tonicState=TonicPatchState(enabled:true,root:5,timbre:0,sound:ExternalSound(kind:.samplerPreset,name:"Generated Missing Recovery Pad",fileName:"generated-missing-recovery-pad.aupreset"),velocitySelector:false,gain:0.2,brightness:0.5,shimmer:0)
            let padBytes=try encoder.encode(missingPad);try padBytes.write(to:previous)
            store.recoverPreviousSession();try retained(padBytes)
        }
        let valid=try encoder.encode(recovered);try valid.write(to:previous)
        store.recoverPreviousSession()
        assert(!store.sessionRecoveryRequired && store.patch.id==recovered.patches[0].id && store.currentSetlistID==nil)
        assert(store.held.isEmpty && !store.sustain && store.activeSnapshot==nil && store.started && store.audio.running)
        assert(store.liveTempo==90 && store.performedTempo==150)
        assert(try! Data(contentsOf:primary)==valid)
        assert(try! Data(contentsOf:previous)==valid)
        let retainedFiles=try archives();assert(retainedFiles.count==1 && (try! Data(contentsOf:retainedFiles[0]))==damaged)
        for i in store.patch.layers.indices {store.setGain(i,0)}
        store.master=1;store.reverb=0;store.metronomeSettings.level=1;store.metronome=true
        var clicks:[Int]=[],quiet=100000,frame=0
        for _ in 0..<400 {
            let block=try store.audio.offlineBlock()
            for i in 0..<Int(block.frameLength) {
                let v=abs(block.floatChannelData![0][i]);assert(v.isFinite)
                if v>0.02 {if quiet>2000 {clicks.append(frame)};quiet=0} else {quiet += 1}
                frame += 1
            }
        }
        assert(clicks.count>=4)
        for i in 2..<clicks.count {assert(abs(clicks[i]-clicks[i-1]-19200)<=8,"Recovered locked tempo must reach the rendered click clock")}
        // Offline document recovery must remain possible without requiring the
        // unavailable playback resources to be repaired first.
        store.stopAudio()
        let unavailable=try encoder.encode(missing)
        try damaged.write(to:primary);try unavailable.write(to:previous)
        let stopped=PerformanceStore();assert(stopped.sessionRecoveryRequired && !stopped.started)
        stopped.recoverPreviousSession()
        assert(!stopped.sessionRecoveryRequired && stopped.patch.id==missing.patches[0].id)
        assert(!stopped.started && !stopped.audio.running)
        assert(try! Data(contentsOf:primary)==unavailable)
        assert(try! Data(contentsOf:previous)==unavailable)
        assert(try! archives().count==2)
        print("PASS live session recovery: missing layer/pad rejection, retained audio/state/bytes, valid retry, damaged archive and rendered tempo")
    }
}
