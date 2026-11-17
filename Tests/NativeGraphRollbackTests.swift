import Foundation
import AVFoundation

@main struct NativeGraphRollbackTests {
    static func main() throws {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        store.showSoundMeters = true
        try store.audio.prepareOffline()
        store.start()
        defer { store.stopAudio() }
        store.audio.space(0)
        for channel in 1..<16 { store.audio.gain(channel, 0, seconds: 0) }
        let rack = store.audio.externalRack!
        let oldUnit = rack.unit(channel: 0)!
        let otherUnit = rack.unit(channel: 1)!
        let oldLayer = store.patch.layers[0]
        store.captureSnapshot(0); store.save()
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let document = root.appendingPathComponent("setlist.json")
        let saved = try Data(contentsOf: document)
        let nodeCount = rack.debugOwnedNodeCount
        let tailCount = rack.debugRetiredTailCount

        func energy() throws -> Double {
            var energy = 0.0
            for _ in 0..<20 {
                let block = try store.audio.offlineBlock()
                for frame in 0..<Int(block.frameLength) {
                    let sample = block.floatChannelData![0][frame]
                    assert(sample.isFinite)
                    energy += Double(sample * sample)
                }
            }
            return energy
        }
        // The generated sample is a 261.626 Hz tone. Project the isolated
        // channel onto the fundamental of each note so either voice can fail
        // independently, even while the other still contributes energy.
        func noteAmplitudes() throws -> [Double] {
            let frequencies = [261.626, 261.626 * pow(2.0, 4.0 / 12.0)]
            var real = [0.0, 0.0], imaginary = [0.0, 0.0]
            var frames = 0
            for _ in 0..<20 {
                let block = try store.audio.offlineBlock()
                for frame in 0..<Int(block.frameLength) {
                    let sample = Double(block.floatChannelData![0][frame])
                    assert(sample.isFinite)
                    for note in frequencies.indices {
                        let phase = 2 * Double.pi * frequencies[note] * Double(frames) / block.format.sampleRate
                        real[note] += sample * cos(phase)
                        imaginary[note] += sample * sin(phase)
                    }
                    frames += 1
                }
            }
            return frequencies.indices.map { 2 * hypot(real[$0], imaginary[$0]) / Double(frames) }
        }
        // One physically held note plus one released under the sustain pedal.
        rack.noteOn(channel: 0, key: 60, pitch: 60, velocity: 0.7, sourceID: 41)
        rack.control(channel: 0, controller: 64, value: 127)
        rack.noteOn(channel: 0, key: 64, pitch: 64, velocity: 0.5, sourceID: 42)
        rack.noteOff(channel: 0, key: 64)
        let originalAmplitudes = try noteAmplitudes()
        assert(rack.debugNoteIntentCount(0) == 2 && originalAmplitudes.allSatisfy { $0 > 0.005 })
        assert((store.audio.soundMeter(0)?.frames ?? 0) > 0, "An enabled meter must receive the active voice")
        for attempt in 0..<6 {
            var starts = 0
            rack.debugGraphFault = { point in
                if case .restartEngine = point {
                    starts += 1
                    if starts == 1 {
                        // Match the reported error shape without implying this
                        // generated restart fault reproduces the device trigger.
                        return NSError(domain: "com.apple.coreaudio.avfaudio", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "PRIVATE-GENERATED-GRAPH-FAILURE"])
                    }
                }
                return nil
            }
            store.commitLayer(0, TestFixtures.layer(1, gain: 0.2))
            assert(starts == 2, "A one-shot forward restart failure must attempt the previous graph")
            assert(store.started && store.audio.running && !store.audioFailed)
            assert(rack.unit(channel: 0) === oldUnit && rack.unit(channel: 1) === otherUnit)
            assert(store.patch.layers[0] == oldLayer && (try! Data(contentsOf: document)) == saved)
            assert(rack.debugOwnedNodeCount == nodeCount && rack.debugRetiredTailCount == tailCount, "Failed candidates must not accumulate nodes/tails, attempt \(attempt)")
            assert(rack.debugNoteIntentCount(0) == 2)
            let restoredAmplitudes = try noteAmplitudes()
            assert(restoredAmplitudes[0] > originalAmplitudes[0] * 0.2, "The held note must render after rollback")
            assert(restoredAmplitudes[1] > originalAmplitudes[1] * 0.2, "The pedal-released note must render after rollback")
            assert((store.audio.soundMeter(0)?.frames ?? 0) > 0, "Rollback must reattach the meter bank to the restored voice, attempt \(attempt)")
            let diagnostic = store.audio.lastChangeFailure!
            let graph = diagnostic.lastGraphFailure!
            assert(diagnostic.phase == .loadInstrument && diagnostic.soundSlot == 1 && diagnostic.engineRunning)
            assert(diagnostic.errorDomain == "com.apple.coreaudio.avfaudio" && diagnostic.errorCode == -1)
            assert(graph.restart?.domain == diagnostic.errorDomain && graph.restart?.code == -1)
            assert(graph.rollbackSucceeded == true && graph.rollback == nil)
            let support = SupportDiagnostics(version: "test", build: "test", running: store.audio.running,
                status: nil, latency: nil, midiSources: 0, loadedSlots: 3, limiterBypassed: false,
                recording: false, lastAudioChangeFailure: diagnostic)
            let json = try support.json()
            let decoded = try JSONDecoder().decode(SupportDiagnostics.self, from: Data(json.utf8))
            assert(decoded.lastAudioChangeFailure == diagnostic && !json.contains("PRIVATE-GENERATED"))
            assert(store.message?.contains("error -1") == true &&
                store.message?.contains("The previous sound remains available") == true &&
                store.message?.contains("try again") == true)
            assert(store.message?.contains(diagnostic.errorDomain) == false &&
                store.message?.contains("PRIVATE-GENERATED") == false,
                "The performer should see recovery guidance without the raw framework error")
        }
        // Fail after wiring a nested imported fan-out, not just at attachment.
        var gain = AudioEffect.factoryDefault(kind: 9); gain.parameters = [-6]
        let split = ImportedRack(audioRacks: [ImportedAudioRack(beforeEffect: 0, name: "Generated split", branches: [
            ImportedAudioBranch(name: "A", rack: ImportedRack(effects: [gain])),
            ImportedAudioBranch(name: "B", rack: ImportedRack(effects: [gain]))
        ])])
        rack.debugGraphFault = { point in
            if case .graphConnected = point { return NSError(domain: NSOSStatusErrorDomain, code: 802) }
            return nil
        }
        for _ in 0..<4 {
            do { try rack.configureImported(channel: 0, rack: split, tempo: 120); assertionFailure("Expected post-routing failure") }
            catch { assert((error as NSError).code == 802) }
            assert(rack.lastGraphFailure?.rollbackSucceeded == true && rack.unit(channel: 0) === oldUnit)
            assert(rack.debugOwnedNodeCount == nodeCount && rack.debugRetiredTailCount == tailCount)
            assert(rack.debugNoteIntentCount(0) == 2 && (try! energy()) > 0.01)
        }
        rack.debugGraphFault = nil
        // Pedal release prunes released notes. A source disconnect then removes
        // its held note; a later graph edit must not resurrect either voice.
        rack.control(channel: 0, controller: 64, value: 0)
        assert(rack.debugNoteIntentCount(0) == 1)
        rack.releaseSource(41)
        assert(rack.debugNoteIntentCount(0) == 0)
        try rack.withGraphChanges { try rack.remove(2) }
        assert(rack.debugNoteIntentCount(0) == 0)
        for _ in 0..<10 { _ = try energy() } // Allow finite release/effect tails to decay.
        let releasedEnergy = try energy()
        print("released energy: \(releasedEnergy)")
        assert(releasedEnergy < 0.000001)

        // A successful edit elsewhere also reloads native samplers. Preserve
        // the original channel's ownership and do not seed the replacement.
        rack.noteOn(channel: 0, key: 67, pitch: 67, velocity: 0.6, sourceID: 43)
        var loaded = false
        rack.load(TestFixtures.layer(1).external!, channel: 2) { result in
            if case .success = result { loaded = true }
        }
        assert(loaded && rack.debugNoteIntentCount(0) == 1 && rack.debugNoteIntentCount(2) == 0)
        assert((try! energy()) > 0.01)
        rack.noteOff(channel: 0, key: 67)
        rack.panic()
        try rack.remove(2)
        for _ in 0..<10 { _ = try energy() }
        assert(rack.debugNoteIntentCount(0) == 0 && (try! energy()) < 0.000001)
        // An outer patch batch has a wider document/MIDI scope than the rack.
        // Even a successful rack rollback must not leave speculative host
        // caches advertised as a running, committed patch.
        var starts = 0
        rack.debugGraphFault = { point in
            if case .restartEngine = point {
                starts += 1
                if starts == 1 { return NSError(domain: NSOSStatusErrorDomain, code: 804) }
            }
            return nil
        }
        do { try store.audio.withGraphChanges { _ = store.audio.configure(0, TestFixtures.layer(1)) }; assertionFailure("Expected batch rejection") }
        catch { assert((error as NSError).code == 804) }
        assert(rack.lastGraphFailure?.rollbackSucceeded == true && !store.started && !store.audio.running && store.audioFailed)
        rack.debugGraphFault = nil
        store.start()
        assert(store.started && store.audio.running && store.patch.layers[0] == oldLayer)
        assert(store.audio.loadedUnit(channel: 0, sound: oldLayer.external) != nil)
        print("PASS native graph rollback: identity, saved bytes, bounded nodes, held/pedal replay and source release")
    }
}
