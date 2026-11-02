import Foundation
import AVFoundation

@main struct NativeLoadFailureTests {
    static func main() throws {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline()
        defer { store.stopAudio() }
        store.start(); store.audio.space(0)
        store.captureSnapshot(0); store.save()
        let previous = store.patch.layers[0]
        let rack = store.audio.externalRack!
        let unit = rack.unit(channel: 0)!
        let generation = rack.graphGeneration
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let original = try encoder.encode(store.setlist)
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let session = root.appendingPathComponent("setlist.json")
        let savedBytes = try Data(contentsOf: session)
        let broken = rack.libraryURL.appendingPathComponent("Malformed.wav")
        try Data("RIFF malformed generated wave".utf8).write(to: broken)
        var proposed = previous
        proposed.name = "Malformed replacement"
        proposed.external = ExternalSound(kind: .sample, name: proposed.name, fileName: broken.lastPathComponent)
        proposed.gain = 0; proposed.pan = 1
        try store.audio.prepareSoundChange(0, proposed) // Exists, so preflight succeeds.

        func energy() throws -> Double {
            var sum = 0.0
            for _ in 0..<20 {
                let block = try store.audio.offlineBlock()
                for frame in 0..<Int(block.frameLength) {
                    let value = block.floatChannelData![0][frame]
                    assert(value.isFinite)
                    sum += Double(value * value)
                }
            }
            return sum
        }
        store.noteOn(60); store.setSustain(true)
        _ = try energy()
        let before = try energy(); assert(before > 0.01)
        store.commitLayer(0, proposed)
        assert(store.patch.layers[0] == previous, "Decoder failure after preflight must retain the original document layer")
        assert(rack.unit(channel: 0) === unit, "Decoder failure must not remove the playing instrument")
        assert(rack.graphGeneration == generation, "Malformed audio must fail before editing the active graph")
        assert(store.held.contains(60) && store.sustain)
        assert(try! encoder.encode(store.setlist) == original)
        assert(try! Data(contentsOf: session) == savedBytes)
        let after = try energy()
        assert(after > before * 0.8 && after < before * 1.2, "Held audio must survive the rejected decoder load")
        assert(store.audio.lastChangeFailure?.phase == .loadInstrument)
        assert(store.audio.lastChangeFailure?.previousSoundRetained == true)
        assert(!store.audio.configure(0, proposed), "Direct callers must receive the synchronous decoder rejection")
        assert(rack.unit(channel: 0) === unit && rack.graphGeneration == generation)
        assert(try! energy() > before * 0.8)
        store.noteOff(60); store.setSustain(false)

        // Fix only the generated input and retry the exact same sound identity.
        // A failed load must not poison the identity cache and skip this attempt.
        let source = root.appendingPathComponent("Generated Fixture 0.wav")
        try Data(contentsOf: source).write(to: broken)
        store.commitLayer(0, proposed)
        assert(store.patch.layers[0] == proposed)
        assert(rack.unit(channel: 0) !== unit)
        store.setGain(0, 0.6); store.noteOn(64)
        assert(try! energy() > 0.001)
        store.noteOff(64)

        // Drive the actual asynchronous instantiate completion path without
        // requiring a third-party plugin. A cancelled callback must not install
        // its candidate over the current native voice or over an empty slot.
        var replies: [(AVAudioUnit?, Error?) -> Void] = []
        rack.debugInstantiate = { _, reply in replies.append(reply) }
        var identity = ExternalAUIdentity(type: 0x61756d75, subtype: 0x74657374, manufacturer: 0x54657374, name: "Generated Deferred AU")
        identity.isV3 = true
        var pending = Layer(name: identity.name, instrument: -1, gain: 0.1)
        pending.external = ExternalSound(kind: .audioUnit, name: identity.name, component: identity)
        var unexpected: [String] = []
        store.audio.onError = { unexpected.append($0) }
        let active = rack.unit(channel: 0)!
        let activeGeneration = rack.graphGeneration
        assert(store.audio.configure(0, pending), "An asynchronous request is accepted, not completed")
        assert(replies.count == 1 && rack.unit(channel: 0) === active)
        assert(store.audio.loadedUnit(channel: 0, sound: pending.external) == nil, "A pending editor must not receive the previous instrument")
        assert(store.audio.loadedUnit(channel: 0, sound: store.patch.layers[0].external) == nil, "State capture waits while a replacement is pending")
        let currentLayer = store.patch.layers[0]
        var documentAU = pending
        documentAU.pluginState = Data("Generated saved AU state".utf8)
        store.setlist.patches[store.selected].layers[0] = documentAU
        store.capturePluginStates()
        store.finishPluginInterface(0)
        assert(store.patch.layers[0].pluginState == documentAU.pluginState, "Pending AU state must not be overwritten by the previous sampler")
        assert(store.saveSoundToLibrary(documentAU, index: 0))
        assert(store.librarySounds.last?.layer?.pluginState == documentAU.pluginState)
        store.setlist.patches[store.selected].layers[0] = currentLayer
        assert(store.audio.configure(0, store.patch.layers[0]))
        assert(store.audio.loadedUnit(channel: 0, sound: store.patch.layers[0].external) === active)
        replies.removeFirst()(AVAudioUnitSampler(), nil)
        func awaitCallback(_ count: Int) {
            let deadline = Date().addingTimeInterval(2)
            while rack.debugInstantiationCallbacks < count && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.005))
            }
            assert(rack.debugInstantiationCallbacks == count, "Deferred callback did not execute")
        }
        awaitCallback(1)
        assert(rack.unit(channel: 0) === active && rack.graphGeneration == activeGeneration)
        store.noteOn(64); assert(try! energy() > 0.001); store.noteOff(64)
        assert(store.audio.configure(3, Layer.empty()))
        let emptyGeneration = rack.graphGeneration
        assert(store.audio.configure(3, pending) && replies.count == 1)
        assert(store.audio.configure(3, Layer.empty()))
        replies.removeFirst()(AVAudioUnitSampler(), nil)
        awaitCallback(2)
        assert(!rack.contains(3) && rack.graphGeneration == emptyGeneration)
        assert(unexpected.isEmpty, "Cancelled callbacks must not report a spurious failure: \(unexpected)")

        // A real instantiation failure result also keeps the active native
        // voice/cache. This is synthetic callback evidence, not real AU fault
        // isolation or a transactional AU document-commit test.
        assert(store.audio.configure(0, pending) && replies.count == 1)
        let failedGeneration = rack.graphGeneration
        replies.removeFirst()(nil, NSError(domain: "com.apple.coreaudio.avfaudio", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "PRIVATE-AU-STATE"] ))
        awaitCallback(3)
        assert(unexpected.count == 1 && !unexpected[0].contains("PRIVATE-AU-STATE"))
        assert(rack.unit(channel: 0) === active && rack.graphGeneration == failedGeneration)
        assert(store.audio.loadedUnit(channel: 0, sound: store.patch.layers[0].external) === active)
        assert(store.audio.lastChangeFailure?.phase == .loadInstrument && store.audio.lastChangeFailure?.errorCode == -1)
        assert(store.audio.configure(0, store.patch.layers[0]))
        store.noteOn(64); assert(try! energy() > 0.001); store.noteOff(64)

        // Same component, different saved state: after a failed reload the old
        // unit must not be mistaken for the newly requested serialized state.
        identity.subtype += 1
        var sameComponent = pending
        sameComponent.external!.component = identity
        assert(store.audio.configure(4, sameComponent) && replies.count == 1)
        replies.removeFirst()(AVAudioUnitSampler(), nil)
        awaitCallback(4)
        let previousAU = store.audio.loadedUnit(channel: 4, sound: sameComponent.external)!
        var newState = sameComponent
        newState.pluginState = try PropertyListSerialization.data(fromPropertyList: ["Generated": 1], format: .binary, options: 0)
        assert(store.audio.configure(4, newState) && replies.count == 1)
        assert(store.audio.loadedUnit(channel: 4, sound: sameComponent.external) == nil)
        replies.removeFirst()(nil, NSError(domain: "com.apple.coreaudio.avfaudio", code: -1))
        awaitCallback(5)
        assert(rack.unit(channel: 4) === previousAU)
        assert(store.audio.loadedUnit(channel: 4, sound: sameComponent.external) == nil)
        assert(try! store.audio.pluginStateData(channel: 4, sound: sameComponent.external) == nil)
        assert(store.audio.configure(4, sameComponent)) // Explicit revert to the already-loaded state.
        assert(store.audio.loadedUnit(channel: 4, sound: sameComponent.external) === previousAU)
        assert(store.audio.configure(4, Layer.empty()))
        rack.debugInstantiate = nil
        print("PASS: post-preflight decoder failure retains held audio, graph/document/save state and permits same-identity retry")
    }
}
