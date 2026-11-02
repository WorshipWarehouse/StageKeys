import Foundation
import AVFoundation

@main struct InstrumentCatalogScopeTests {
    static func main() throws {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline(); store.start()
        defer { store.stopAudio() }
        let rack = store.audio.externalRack!
        var installed: [ExternalAUIdentity] = []
        for channel in [0, 1] {
            let identity = ExternalAUIdentity(type: 0x61756d75, subtype: 0x73636f30 + UInt32(channel), manufacturer: 0x54657374, name: "Generated scoped catalog \(channel)")
            installed.append(identity)
            store.setlist.patches[1].layers[channel].external = ExternalSound(kind: .audioUnit, name: identity.name, component: identity)
        }
        let available = installed
        var reads = 0
        rack.debugInstrumentCatalog = { reads += 1; return installed }
        var replies: [(AVAudioUnit?, Error?) -> Void] = []
        rack.debugInstantiate = { _, reply in replies.append(reply) }
        func deliverStale() {
            let count = rack.debugInstantiationCallbacks + replies.count
            let callbacks = replies; replies.removeAll()
            callbacks.forEach { $0(nil, NSError(domain: NSOSStatusErrorDomain, code: -1)) }
            let deadline = Date().addingTimeInterval(2)
            while rack.debugInstantiationCallbacks < count && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
            assert(rack.debugInstantiationCallbacks == count)
        }
        store.choose(1)
        assert(reads == 1 && replies.count == 2 && store.patchLoading, "Selection, preparation and two load requests must share one registry read")
        store.choose(2)
        let unit = rack.unit(channel: 0)!
        deliverStale()
        assert(reads == 1 && store.selected == 2 && !store.patchLoading && store.started && rack.unit(channel: 0) === unit)
        installed = []
        store.choose(1)
        assert(reads == 2 && store.selected == 2 && replies.isEmpty, "The next interaction must observe removal and reject before instantiate")
        store.choose(0)
        assert(reads == 2, "Native-only selection must not enumerate AU components")
        installed = available
        try store.audio.preparePatchResources(store.setlist.patches[1].layers)
        assert(reads == 3, "Standalone patch preparation must share its own fresh snapshot")
        let target = store.setlist.patches[1].layers[0]
        assert(store.audio.configure(0, target))
        assert(reads == 4 && replies.count == 1, "Standalone configure must share preflight and load validation")
        assert(store.audio.configure(0, store.patch.layers[0]))
        deliverStale()
        assert(reads == 4)
        enum Expected: Error { case stop }
        do {
            try rack.withInstrumentCatalog {
                try rack.validateSound(target.external!)
                try rack.withInstrumentCatalog { try rack.validateSound(store.setlist.patches[1].layers[1].external!) }
                assert(reads == 5)
                throw Expected.stop
            }
        } catch Expected.stop {}
        installed = []
        do { try rack.validateSound(target.external!); assertionFailure("An exception leaked the cached registry") } catch {}
        assert(reads == 6)
        installed = available
        try rack.withInstrumentCatalog {
            try rack.validateSound(target.external!)
            installed = [] // Registry changes cannot produce a mixed view within this synchronous operation.
            try rack.validateSound(target.external!)
        }
        assert(reads == 7)
        do { try rack.validateSound(target.external!); assertionFailure("Snapshot survived operation exit") } catch {}
        assert(reads == 8)
        assert(!(try! ExternalInstrumentRack.blockedComponentIDs()).contains(available[0].id))
        print("PASS scoped AU catalog: one read per operation, lazy native path, nested scopes, fresh removal and exception cleanup")
    }
}
