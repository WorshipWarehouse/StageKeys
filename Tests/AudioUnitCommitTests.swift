import Foundation
import AVFoundation

@main struct AudioUnitCommitTests {
    static func main() throws {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline(); store.start()
        defer { store.stopAudio() }
        store.captureSnapshot(0); store.save()
        let rack = store.audio.externalRack!
        var replies: [(AVAudioUnit?, Error?) -> Void] = []
        rack.debugInstantiate = { _, reply in replies.append(reply) }
        let identity = ExternalAUIdentity(type: 0x61756d75, subtype: 0x74657374, manufacturer: 0x54657374, name: "Generated AU")
        var proposed = Layer(name: identity.name, instrument: -1, gain: 0.2)
        proposed.id = store.patch.layers[0].id
        proposed.external = ExternalSound(kind: .audioUnit, name: identity.name, component: identity)
        let previous = store.patch.layers[0]
        let unit = rack.unit(channel: 0)!
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let path = root.appendingPathComponent("setlist.json")
        let saved = try Data(contentsOf: path)
        func reply(_ candidate: AVAudioUnit?, _ error: Error? = nil) {
            let expected = rack.debugInstantiationCallbacks + 1
            assert(!replies.isEmpty, "Expected a generated instantiate request")
            replies.removeFirst()(candidate, error)
            let deadline = Date().addingTimeInterval(2)
            while rack.debugInstantiationCallbacks < expected && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.005))
            }
            assert(rack.debugInstantiationCallbacks == expected)
        }
        store.noteOn(60); store.setSustain(true)
        try ExternalInstrumentRack.allowBlockedLoads()
        store.commitLayer(0, proposed)
        assert(replies.count == 1 && store.patch.layers[0] == previous && rack.unit(channel: 0) === unit)
        assert((try! Data(contentsOf: path)) == saved && store.held.contains(60) && store.sustain)
        reply(nil, NSError(domain: NSOSStatusErrorDomain, code: -1))
        assert(store.patch.layers[0] == previous && rack.unit(channel: 0) === unit)
        assert((try! Data(contentsOf: path)) == saved && store.held.contains(60) && store.sustain)

        // State validation executes inside candidate installation, before a
        // successful completion can publish or persist the new document.
        var malformed = proposed; malformed.pluginState = Data("generated invalid plist".utf8)
        try ExternalInstrumentRack.allowBlockedLoads()
        store.commitLayer(0, malformed)
        let rejected = AVAudioUnitSampler()
        reply(rejected)
        assert(store.patch.layers[0] == previous && rack.unit(channel: 0) === unit && rejected.engine == nil)
        assert(store.started && store.audio.running && rack.lastGraphFailure?.rollbackSucceeded == true)
        assert((try! Data(contentsOf: path)) == saved && store.held.contains(60))

        // The state setter has run, but the staged candidate is rejected before
        // installation completion. This is a deterministic boundary fault, not
        // evidence that an arbitrary third-party setter exception is catchable.
        try ExternalInstrumentRack.allowBlockedLoads()
        var stateful = proposed
        stateful.pluginState = try rack.stateData(channel: 0)
        rack.debugGraphFault = { point in
            if case .pluginStateApplied = point { return NSError(domain: NSOSStatusErrorDomain, code: 803) }
            return nil
        }
        store.commitLayer(0, stateful)
        reply(AVAudioUnitSampler())
        assert(store.patch.layers[0] == previous && rack.unit(channel: 0) === unit && store.audio.running)
        assert(rack.lastGraphFailure?.operation?.code == 803 && rack.lastGraphFailure?.rollbackSucceeded == true)
        assert((try! Data(contentsOf: path)) == saved)
        rack.debugGraphFault = nil

        // A user edit while loading invalidates the pending proposal. It must
        // preserve that newer edit rather than installing a stale AU over it.
        try ExternalInstrumentRack.allowBlockedLoads()
        store.commitLayer(0, proposed)
        store.setGain(0, 0.4)
        let edited = store.patch.layers[0]
        reply(AVAudioUnitSampler())
        assert(store.patch.layers[0] == edited && rack.unit(channel: 0) === unit)

        // Newer native selection supersedes an older callback entirely.
        try ExternalInstrumentRack.allowBlockedLoads()
        store.commitLayer(0, proposed)
        let native = TestFixtures.layer(1)
        store.commitLayer(0, native)
        let nativeUnit = rack.unit(channel: 0)!
        reply(AVAudioUnitSampler())
        assert(store.patch.layers[0] == native && rack.unit(channel: 0) === nativeUnit)

        // Publish exactly once on accepted completion, including editor intent
        // registered while the library sheet was still open.
        try ExternalInstrumentRack.allowBlockedLoads()
        store.commitLayer(0, proposed)
        store.requestPluginInterface(0)
        assert(store.takePluginInterfaceRequest() == nil)
        let accepted = AVAudioUnitSampler()
        reply(accepted)
        assert(store.patch.layers[0].external == proposed.external && store.patch.layers[0].gain == proposed.gain && rack.unit(channel: 0) === accepted)
        assert(store.patch.layers[0].pluginState != nil, "The successful save captures the accepted plugin state")
        assert(store.audio.loadedUnit(channel: 0, sound: proposed.external) === accepted)
        assert(store.takePluginInterfaceRequest() == 0 && store.takePluginInterfaceRequest() == nil)
        assert((try! Data(contentsOf: path)) != saved)
        assert(!store.held.isEmpty, "Existing Store held-key policy is preserved; per-layer voices are panicked at commit")
        print("PASS deferred AU document commit, rejected state rollback, supersession and editor intent")
    }
}
