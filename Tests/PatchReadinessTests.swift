import Foundation
import AVFoundation

@main struct PatchReadinessTests {
    static func main() throws {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline(); store.start()
        defer { store.stopAudio() }
        let rack = store.audio.externalRack!
        var replies: [(AVAudioUnit?, Error?) -> Void] = []
        rack.debugInstantiate = { _, reply in replies.append(reply) }
        for channel in [0, 1] {
            var identity = ExternalAUIdentity(type: 0x61756d75, subtype: 0x70617430 + UInt32(channel), manufacturer: 0x54657374, name: "Generated patch AU \(channel)")
            identity.isV3 = true
            store.setlist.patches[1].layers[channel].external = ExternalSound(kind: .audioUnit, name: identity.name, component: identity)
        }
        store.setlist.patches[1].silencePrevious = true
        store.save()
        let path = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!).appendingPathComponent("setlist.json")
        let saved = try Data(contentsOf: path)
        func reply(_ index: Int, failure: Bool = false) {
            let count = rack.debugInstantiationCallbacks + 1
            let callback = replies.remove(at: index)
            if failure { callback(nil, NSError(domain: NSOSStatusErrorDomain, code: -1)) }
            else {
                let unit = AVAudioUnitSampler()
                try! SamplerRendering.configure(unit, offline: true, resident: true)
                let source = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!).appendingPathComponent("Generated Fixture 0.wav")
                try! unit.loadAudioFiles(at: [source])
                callback(unit, nil)
            }
            let deadline = Date().addingTimeInterval(2)
            while rack.debugInstantiationCallbacks < count && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
            assert(rack.debugInstantiationCallbacks == count)
        }
        store.choose(1)
        assert(replies.count == 2 && store.patchLoading && store.audioStatusText == "Loading patch…")
        store.noteOn(60); assert(store.held.isEmpty)
        let pendingLayers = store.patch.layers
        store.recall(store.patch.snapshots[0])
        assert(store.patch.layers == pendingLayers && store.activeSnapshot == nil && store.message?.contains("finish loading") == true)
        reply(1)
        assert(store.patchLoading && !store.audioFailed)
        store.noteOn(64); assert(store.held.isEmpty)
        rack.noteOn(channel: 1, key: 70, pitch: 70, velocity: 0.8)
        var pendingEnergy = 0.0
        for _ in 0..<20 {
            let block = try store.audio.offlineBlock()
            for frame in 0..<Int(block.frameLength) { let v = block.floatChannelData![0][frame]; pendingEnergy += Double(v * v) }
        }
        rack.noteOff(channel: 1, key: 70)
        assert(pendingEnergy < 0.000001, "A ready slot must remain muted while another slot is pending")
        reply(0, failure: true)
        assert(!store.patchLoading && !store.started && !store.audio.running && store.audioFailed)
        assert(store.selected == 1 && store.audio.lastChangeFailure?.errorCode == -1)
        assert((try! Data(contentsOf: path)) == saved, "Loading failure must not rewrite the authored setlist")
        try ExternalInstrumentRack.allowBlockedLoads()
        store.start()
        assert(store.patchLoading && replies.count == 2)
        reply(0)
        assert(store.patchLoading)
        reply(0)
        assert(!store.patchLoading && store.started && store.audio.running && store.audioStatusText == "Running")
        store.audio.space(0)
        store.noteOn(60); assert(store.held.contains(60))
        var energy = 0.0
        for _ in 0..<30 {
            let block = try store.audio.offlineBlock()
            for frame in 0..<Int(block.frameLength) { let v = block.floatChannelData![0][frame]; assert(v.isFinite); energy += Double(v * v) }
        }
        assert(energy > 0.01, "All-ready retry must render accepted candidates")
        store.noteOff(60)

        // Superseding a patch cancels old callbacks without stopping the newer
        // native patch or installing the late units over it.
        store.choose(0); store.choose(1)
        assert(store.patchLoading && replies.count == 2)
        store.choose(2)
        let active = rack.unit(channel: 0)!
        reply(1); reply(0)
        assert(store.selected == 2 && !store.patchLoading && store.started && rack.unit(channel: 0) === active)
        store.choose(1)
        assert(store.patchLoading && replies.count == 2)
        store.stopAudio()
        reply(0); reply(0)
        assert(!store.started && !store.audio.running && !store.patchLoading && store.audioStartup == .stopped)
        // A synchronous processing rejection inside the enclosing patch batch
        // must not be followed by an outer restart that leaves failed UI with
        // a running engine.
        store.choose(0); store.start()
        assert(store.started && !store.patchLoading)
        store.setlist.patches[2].layers[0].importedRack = ImportedRack(audioRacks: [ImportedAudioRack(beforeEffect: 0, name: "Generated failing topology", branches: [ImportedAudioBranch(name: "Generated", rack: ImportedRack())])])
        rack.debugGraphFault = { point in
            if case .graphConnected = point { return NSError(domain: NSOSStatusErrorDomain, code: 904) }
            return nil
        }
        store.choose(2)
        assert(!store.started && !store.audio.running && store.audioFailed && !store.patchLoading)
        assert(store.audio.lastChangeFailure?.errorCode == 904)
        rack.debugGraphFault = nil
        store.start()
        assert(store.started && store.audio.running && !store.patchLoading)
        print("PASS patch readiness: await all AUs, failure/retry, note gating, stale callbacks and stop")
    }
}
