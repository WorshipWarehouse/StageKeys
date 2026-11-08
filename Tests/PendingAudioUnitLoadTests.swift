import Foundation
import AVFoundation

@main struct PendingAudioUnitLoadTests {
    static func main() throws {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline(); store.start()
        defer { store.stopAudio() }
        store.audio.space(0)
        for channel in 1..<15 { store.audio.gain(channel, 0, seconds: 0) }
        store.save()
        let rack = store.audio.externalRack!
        let unit = rack.unit(channel: 0)!
        let generation = rack.graphGeneration
        let previous = store.patch.layers[0]
        let path = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!).appendingPathComponent("setlist.json")
        let saved = try Data(contentsOf: path)
        var replies: [(AVAudioUnit?, Error?) -> Void] = []
        rack.debugInstantiate = { _, reply in replies.append(reply) }
        let identity = ExternalAUIdentity(type: 0x61756d75, subtype: 0x706f6f6c, manufacturer: 0x54657374, name: "PRIVATE-generated stalled AU")
        let sound = ExternalSound(kind: .audioUnit, name: identity.name, component: identity)
        func wait(_ predicate: () -> Bool) {
            let deadline = Date().addingTimeInterval(2)
            while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
            assert(predicate())
        }
        func energy() throws -> Double {
            var sum = 0.0
            for _ in 0..<20 {
                let block = try store.audio.offlineBlock()
                for frame in 0..<Int(block.frameLength) { let value = block.floatChannelData![0][frame]; assert(value.isFinite); sum += Double(value * value) }
            }
            return sum
        }
        store.noteOn(60); store.setSustain(true)
        let before = try energy(); assert(before > 0.01)
        var completions = 0
        for _ in 0..<32 {
            rack.load(sound, channel: 0) { _ in completions += 1 }
            rack.cancelPendingLoad(0)
        }
        assert(replies.count == 32 && rack.debugPendingInstantiationCount == 32)
        var rejected: NSError?
        rack.load(sound, channel: 0) { if case .failure(let error) = $0 { rejected = error as NSError } }
        assert(replies.count == 32 && rejected?.domain == ExternalInstrumentRack.loadCapacityErrorDomain)
        let otherAudio = AudioController()
        defer { otherAudio.stop() }
        let otherRack = otherAudio.externalRack!
        var otherSubmissions = 0
        otherRack.debugInstantiate = { _, _ in otherSubmissions += 1 }
        var otherRejected = false
        otherRack.load(sound, channel: 0) { if case .failure = $0 { otherRejected = true } }
        assert(otherRejected && otherSubmissions == 0 && otherRack.debugPendingInstantiationCount == 32, "A new rack must not bypass process admission")
        otherRack.resetForRecovery()
        assert(rack.debugPendingInstantiationCount == 32)
        var proposed = Layer(name: identity.name, instrument: -1, gain: 0.4); proposed.external = sound
        store.commitLayer(0, proposed)
        assert(store.patch.layers[0] == previous && rack.unit(channel: 0) === unit && rack.graphGeneration == generation)
        assert(store.held.contains(60) && store.sustain && (try! energy()) > before * 0.7)
        assert(store.message?.contains("Wait") == true && replies.count == 32)
        let diagnostic = store.audio.lastChangeFailure!
        assert(diagnostic.errorDomain == ExternalInstrumentRack.loadCapacityErrorDomain && diagnostic.previousSoundRetained == true)
        let report = SupportDiagnostics(version: "test", build: "test", running: true, status: nil, latency: nil,
            midiSources: 0, loadedSlots: 3, limiterBypassed: false, recording: false, lastAudioChangeFailure: diagnostic)
        let json = try report.json()
        assert(!json.contains("PRIVATE"))
        assert(try! JSONDecoder().decode(SupportDiagnostics.self, from: Data(json.utf8)).lastAudioChangeFailure == diagnostic)
        // Recovery resets voices, not unresolved backend ownership.
        store.setlist.patches[1].layers[0] = proposed
        store.choose(1)
        assert(store.audioFailed && !store.audio.running && store.audioFailureMessage?.contains("Wait") == true)
        assert(store.message?.contains("Wait") == true && store.message?.contains("previous sound remains") != true, "Stopped patch failure must not claim a previous sound is still available")
        store.choose(0); store.start()
        assert(store.started && store.audio.running && rack.debugPendingInstantiationCount == 32)
        let oldReply = replies.removeFirst()
        let cancelled = AVAudioUnitSampler(); oldReply(cancelled, nil)
        wait { rack.debugPendingInstantiationCount == 31 }
        assert(cancelled.engine == nil)
        assert(store.audio.configure(3, proposed) && replies.count == 32)
        assert(rack.debugPendingInstantiationCount == 32)
        assert(store.audio.configure(3, Layer.empty()))
        let remaining = replies; replies.removeAll()
        remaining.forEach { $0(nil, nil) }
        wait { rack.debugPendingInstantiationCount == 0 }
        assert(completions == 32 && (try! ExternalInstrumentRack.blockedComponentIDs()).isEmpty)
        assert((try! Data(contentsOf: path)) == saved)
        // Timeout completes the host result, but cannot free an unresolved
        // backend lease. A later callback releases it without attaching a unit
        // or completing the host request twice.
        rack.debugInstantiationTimeout = 0.02
        var timedOut = 0
        rack.load(sound, channel: 3) { result in
            if case .failure(let error) = result { assert((error as NSError).code == 2); timedOut += 1 }
        }
        wait { timedOut == 1 }
        assert(rack.debugPendingInstantiationCount == 1 && (try! ExternalInstrumentRack.blockedComponentIDs()).contains(identity.id))
        let late = AVAudioUnitSampler(), lateReply = replies.removeFirst()
        lateReply(late, nil)
        wait { rack.debugPendingInstantiationCount == 0 }
        assert(timedOut == 1 && late.engine == nil && !rack.contains(3))
        try ExternalInstrumentRack.allowBlockedLoad(identity.id)
        rack.debugInstantiationTimeout = 10
        assert(store.audio.configure(3, proposed) && replies.count == 1)
        lateReply(nil, nil) // A duplicate old callback must not release a newer ticket.
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        assert(rack.debugPendingInstantiationCount == 1 && timedOut == 1)
        let ready = AVAudioUnitSampler()
        try SamplerRendering.configure(ready, offline: true, resident: true)
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        try ready.loadAudioFiles(at: [root.appendingPathComponent("Generated Fixture 0.wav")])
        replies.removeFirst()(ready, nil)
        wait { rack.debugPendingInstantiationCount == 0 }
        assert(store.audio.loadedUnit(channel: 3, sound: sound) === ready)
        for channel in 0..<15 { store.audio.gain(channel, channel == 3 ? 0.6 : 0, seconds: 0) }
        store.audio.noteOn(key: 700, pitch: 60, instrument: -1, layer: 3, velocity: 0.7)
        assert((try! energy()) > 0.01)
        store.audio.noteOff(key: 700, channel: 3)

        // An audition begun before its AU finishes loading must adopt the unit
        // installed by confirmation. Otherwise the commit requests a reload and
        // cuts notes started after loading completed.
        var delayed = proposed
        delayed.id = store.patch.layers[4].id
        store.setlist.patches[store.selected].layers[4] = delayed
        try ExternalInstrumentRack.allowBlockedLoads()
        assert(store.audio.configure(4, delayed) && replies.count == 1)
        assert(store.audio.loadedUnit(channel: 4, sound: delayed.external) == nil)
        let delayedToken = store.beginAudition(4)!
        let readyDelayed = AVAudioUnitSampler()
        try SamplerRendering.configure(readyDelayed, offline: true, resident: true)
        try readyDelayed.loadAudioFiles(at: [root.appendingPathComponent("Generated Fixture 0.wav")])
        replies.removeFirst()(readyDelayed, nil)
        wait { rack.debugPendingInstantiationCount == 0 }
        assert(store.audio.loadedUnit(channel: 4, sound: delayed.external) === readyDelayed)
        store.audio.gain(4, 0.6, seconds: 0)
        store.audio.noteOn(key: 701, pitch: 60, instrument: -1, layer: 4, velocity: 0.7)
        let activeDelayed = rack.debugActiveNoteCount(4)
        let intentDelayed = rack.debugNoteIntentCount(4)
        let delayedGeneration = rack.graphGeneration
        let instantiationCallbacks = rack.debugInstantiationCallbacks
        rack.debugClearMIDIEvents()
        var confirmedDelayed = delayed
        confirmedDelayed.channelSettings.resonance = 2
        store.previewLayer(4, confirmedDelayed, token: delayedToken)
        store.confirmAudition(delayedToken, index: 4, layer: confirmedDelayed)
        let disruptive = rack.debugMIDIEvents.contains {
            let kind = $0.status & 0xf0
            return kind == 0x80 || kind == 0x90 ||
                (kind == 0xb0 && ($0.data1 == 120 || $0.data1 == 123 || ($0.data1 == 64 && $0.data2 < 64)))
        }
        assert(!disruptive, "Confirm must not send note, panic, or sustain-off MIDI events")
        assert(rack.debugInstantiationCallbacks == instantiationCallbacks,
               "Confirm must adopt the loaded AU instead of requesting a reload")
        assert(rack.debugPendingInstantiationCount == 0)
        assert(rack.unit(channel: 4) === readyDelayed)
        assert(store.audio.loadedUnit(channel: 4, sound: delayed.external) === readyDelayed)
        assert(rack.graphGeneration == delayedGeneration)
        assert(rack.debugActiveNoteCount(4) == activeDelayed && rack.debugNoteIntentCount(4) == intentDelayed,
               "Confirm must retain notes started after the AU finished loading")
        assert(store.patch.layers[4].channelSettings.resonance == 2)
        assert((try! energy()) > 0.01)
        store.audio.noteOff(key: 701, channel: 4)
        print("PASS AU admission: bounded cancelled requests, retained native audio, recovery ownership, timeout leases, late callback, rendered retry and pending-load audition adoption")
    }
}
