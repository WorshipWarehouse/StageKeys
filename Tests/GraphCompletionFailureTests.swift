import Foundation
import AVFoundation

@main struct GraphCompletionFailureTests {
    static func main() throws {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline()
        defer { store.stopAudio() }
        store.start()
        store.tonicSound = TestFixtures.padSound()
        store.toggleTonic(0)
        store.metronome = true
        store.captureSnapshot(0); store.save()
        let rack = store.audio.externalRack!
        let old = store.patch.layers[0]
        let oldUnit = rack.unit(channel: 0)!
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(store.setlist)
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let saved = try Data(contentsOf: root.appendingPathComponent("setlist.json"))
        let settings = try Data(contentsOf: root.appendingPathComponent("settings.json"))
        let snapshot = store.activeSnapshot
        let pad = store.tonicSound
        store.noteOn(60); store.setSustain(true)
        rack.debugGraphFault = { point in
            switch point {
            case .candidateAttached:
                return NSError(domain: "GeneratedOperation", code: 701, userInfo: [NSLocalizedDescriptionKey: "PRIVATE-CANDIDATE"])
            case .restartEngine:
                return NSError(domain: "com.apple.coreaudio.avfaudio", code: 702, userInfo: [NSLocalizedDescriptionKey: "PRIVATE-RESTART"])
            case .restoreSamplers, .graphConnected, .pluginStateApplied: return nil
            }
        }
        store.commitLayer(0, TestFixtures.layer(1, gain: 0.3))
        assert(!store.audio.running, "Injected restart failure must leave the engine stopped")
        assert(!store.started && store.audioFailed, "A graph cleanup failure must not leave the UI reporting Running")
        assert(store.audioStartup.failure?.kind == .graphRecoveryRequired)
        assert(store.audioFailureMessage?.contains("702") == true)
        assert(store.audio.lastChangeFailure?.errorCode == 701)
        let failureID = store.audio.lastChangeFailure!.requestID
        let failureGeneration = rack.graphGeneration
        store.startAutomatically()
        assert(!store.started && !store.audio.running && store.audioFailed)
        assert(store.audio.lastChangeFailure?.requestID == failureID && rack.graphGeneration == failureGeneration, "Automatic view startup must not retry a failed performance")
        let graph = store.audio.lastChangeFailure!.lastGraphFailure!
        assert(graph.operation?.code == 701 && graph.restart?.code == 702 && graph.restoration == nil)
        assert(graph.edited && graph.wasRunning && !graph.engineRunning)
        let report = try JSONEncoder().encode(graph)
        assert(!String(decoding: report, as: UTF8.self).contains("PRIVATE"))
        let support = SupportDiagnostics(version: "test", build: "test", running: false, status: nil, latency: nil,
            midiSources: 0, loadedSlots: 3, limiterBypassed: false, recording: false,
            lastAudioChangeFailure: store.audio.lastChangeFailure)
        let json = try support.json()
        let decoded = try JSONDecoder().decode(SupportDiagnostics.self, from: Data(json.utf8))
        assert(decoded.lastAudioChangeFailure?.lastGraphFailure == graph && !json.contains("PRIVATE"))
        assert(store.held.isEmpty && !store.sustain, "Stopped audio must not retain stale note/pedal ownership")
        assert(store.metronome && store.tonic == 0 && store.tonicSound == pad && store.activeSnapshot == snapshot)
        assert(store.patch.layers[0] == old && rack.unit(channel: 0) === oldUnit)
        assert(rack.debugLastCandidate?.engine == nil, "The rejected candidate must be detached")
        assert(try! encoder.encode(store.setlist) == before)
        assert(try! Data(contentsOf: root.appendingPathComponent("setlist.json")) == saved)
        assert(try! Data(contentsOf: root.appendingPathComponent("settings.json")) == settings)
        rack.debugGraphFault = nil
        store.start()
        assert(store.started && store.audio.running, "Manual retry must recover without relaunch")
        assert(rack.unit(channel: 0) !== oldUnit, "Retry must rebuild the saved instrument rather than trust stale caches")
        assert(rack.debugActiveNoteCount(15) > 0 && store.metronome, "Retry must resume the selected pad and click policy")

        func verifyFreshNotes() throws {
            for i in 1..<16 { store.audio.gain(i, 0, seconds: 0) }
            store.audio.metronome(false, settings: store.metronomeSettings)
            store.audio.space(0)
            store.noteOn(64)
            var peak: Float = 0
            for _ in 0..<20 {
                let buffer = try store.audio.offlineBlock()
                for frame in 0..<Int(buffer.frameLength) {
                    let sample = buffer.floatChannelData![0][frame]
                    assert(sample.isFinite); peak = max(peak, abs(sample))
                }
            }
            store.noteOff(64)
            assert(peak > 0.001, "Saved native instrument must render after recovery, isolated from pad/click")
        }
        try verifyFreshNotes()

        // A restore failure must not start a partially restored graph.
        var restarts = 0
        rack.debugGraphFault = { point in
            if case .restoreSamplers = point { return NSError(domain: NSOSStatusErrorDomain, code: 703) }
            if case .restartEngine = point { restarts += 1 }
            return nil
        }
        store.commitLayer(0, TestFixtures.layer(1, gain: 0.3))
        assert(!store.audio.running && !store.started && store.audioFailed && restarts == 0)
        let restoreFailure = store.audio.lastChangeFailure!.lastGraphFailure!
        assert(restoreFailure.operation == nil && restoreFailure.restoration?.code == 703 && restoreFailure.restart == nil)
        assert(restoreFailure.rollbackSucceeded == false && restoreFailure.rollback?.code == 703,
            "A failed rollback must be recorded separately from the forward restoration failure")
        assert(store.audioFailed && store.audioFailureMessage?.contains("Audio stopped during a sound change") == true)
        assert(try! encoder.encode(store.setlist) == before)
        assert(try! Data(contentsOf: root.appendingPathComponent("setlist.json")) == saved)
        rack.debugGraphFault = nil; store.start()
        assert(store.started && store.audio.running)
        try verifyFreshNotes()

        // Preserve typed operation errors while recording a separate cleanup
        // error; native callers' catch contracts must remain intact.
        enum OperationFailure: Error { case expected }
        rack.debugGraphFault = { point in
            if case .restartEngine = point { return NSError(domain: NSOSStatusErrorDomain, code: 704) }
            return nil
        }
        var caught = false
        do {
            try store.audio.withGraphChanges {
                try rack.remove(2)
                throw OperationFailure.expected
            }
        } catch OperationFailure.expected { caught = true }
        assert(caught && !store.started && store.audioFailed)
        let combined = store.audio.lastChangeFailure!.lastGraphFailure!
        assert(combined.operation != nil && combined.restart?.code == 704)
        rack.debugGraphFault = nil; store.start()
        assert(store.started && store.audio.running && rack.unit(channel: 2) != nil)
        try verifyFreshNotes()

        // Attachment failure with successful cleanup keeps the original unit
        // usable. This checks fresh-note recovery, not seamless held-note phase.
        let retained = rack.unit(channel: 0)!
        rack.debugGraphFault = { point in
            if case .candidateAttached = point { return NSError(domain: NSOSStatusErrorDomain, code: 705) }
            return nil
        }
        store.commitLayer(0, TestFixtures.layer(1, gain: 0.3))
        assert(store.started && store.audio.running && rack.unit(channel: 0) === retained)
        let recovered = store.audio.lastChangeFailure!.lastGraphFailure!
        assert(recovered.operation?.code == 705 && recovered.restoration == nil && recovered.restart == nil)
        assert(try! encoder.encode(store.setlist) == before)
        rack.debugGraphFault = nil
        try verifyFreshNotes()

        // The Tonic picker calls the rack directly: it must enter the same
        // stopped state and keep its previous selection instead of recursively
        // trying to restore a graph whose completion already failed.
        rack.debugGraphFault = { point in
            if case .candidateAttached = point { return NSError(domain: NSOSStatusErrorDomain, code: 706) }
            if case .restartEngine = point { return NSError(domain: NSOSStatusErrorDomain, code: 707) }
            return nil
        }
        store.setTonicInstrument(pad!)
        assert(!store.started && !store.audio.running && store.audioFailed && !store.tonicSoundLoading)
        assert(store.tonicSound == pad && store.tonic == 0 && store.metronome)
        assert(store.audio.lastChangeFailure?.soundSlot == 16)
        assert(store.audio.lastChangeFailure?.lastGraphFailure?.operation?.code == 706)
        assert(store.audio.lastChangeFailure?.lastGraphFailure?.restart?.code == 707)
        assert(try! encoder.encode(store.setlist) == before)
        assert(try! Data(contentsOf: root.appendingPathComponent("setlist.json")) == saved)
        assert(try! Data(contentsOf: root.appendingPathComponent("settings.json")) == settings)
        rack.debugGraphFault = nil; store.start()
        assert(store.started && store.audio.running && rack.debugActiveNoteCount(15) > 0)
        try verifyFreshNotes()

        // A rejected device/route transaction (manual rendering cannot change a
        // live output) must be an operation-scoped device diagnostic and must
        // not silently switch off the selected pad or the click. The previous
        // code called the generic panic(), which cleared both properties.
        store.tonicSound = pad
        if store.tonic == nil { store.toggleTonic(0) }
        assert(store.tonic == 0 && store.tonicSound == pad)
        store.metronome = true
        store.selectAudioOutput(0)
        assert(store.audio.lastChangeFailure?.phase == .audioDevice)
        assert(store.metronome && store.tonic == 0 && store.tonicSound == pad,
            "A failed device change must retain the pad and click choices")
        assert(store.message?.contains("audio device") == true && store.message?.contains("PRIVATE") != true)
        assert(store.message?.contains("couldn’t") != true && store.message?.contains("The operation") != true)
        assert(rack.debugActiveNoteCount(15) > 0, "The pad must be retriggered after the rejected transaction")
        store.setAudioBuffer(128)
        assert(store.audio.lastChangeFailure?.phase == .audioDevice)
        assert(store.metronome && store.tonic == 0 && store.tonicSound == pad)
        assert(try! Data(contentsOf: root.appendingPathComponent("settings.json")) == settings,
            "A rejected device setting must not be persisted")
        store.audio.metronome(false, settings: store.metronomeSettings)
        var padEnergy = 0.0
        for _ in 0..<30 {
            let buffer = try store.audio.offlineBlock()
            for frame in 0..<Int(buffer.frameLength) {
                let sample = buffer.floatChannelData![0][frame]
                assert(sample.isFinite); padEnergy += Double(sample * sample)
            }
        }
        assert(padEnergy > 0.000001, "The retained pad must still render after a rejected device change")

        // Fault injection for the exact AVFAudio -1 shape, not a real device
        // reproduction: the underlying numeric cause is retained without the
        // raw description and without attaching a stale rack graph failure.
        let injectedResume = NSError(domain: "com.apple.coreaudio.avfaudio", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "PRIVATE-AVFAUDIO-DESCRIPTION"])
        let injectedFailure = store.audio.recordAudioDeviceFailure(AudioDeviceError.resumeFailed(injectedResume))
        assert(injectedFailure.diagnostic.phase == .audioDevice)
        assert(injectedFailure.diagnostic.errorDomain == "com.apple.coreaudio.avfaudio" && injectedFailure.diagnostic.errorCode == -1)
        assert(injectedFailure.diagnostic.lastGraphFailure == nil, "A device failure must not attach a stale graph failure")
        assert(injectedFailure.localizedDescription.contains("-1") && !injectedFailure.localizedDescription.contains("PRIVATE"))
        print("PASS: graph cleanup failure is visible and manual retry restores the saved patch")
    }
}
