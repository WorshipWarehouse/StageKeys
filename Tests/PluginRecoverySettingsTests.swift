import Foundation
import AVFoundation

@main struct PluginRecoverySettingsTests {
    static func main() throws {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline(); store.start()
        defer { store.stopAudio() }
        let rack = store.audio.externalRack!
        var replies: [(AVAudioUnit?, Error?) -> Void] = []
        rack.debugInstantiate = { _, reply in replies.append(reply) }
        for channel in [0, 1] {
            let identity = ExternalAUIdentity(type: 0x61756d75, subtype: 0x72656330 + UInt32(channel), manufacturer: 0x54657374, name: "Generated recovery instrument \(channel)")
            store.setlist.patches[1].layers[channel].external = ExternalSound(kind: .audioUnit, name: identity.name, component: identity)
        }
        let ids = [0, 1].map { store.setlist.patches[1].layers[$0].external!.component!.id }
        func replyFailure() {
            let count = rack.debugInstantiationCallbacks + 1
            replies.removeFirst()(nil, NSError(domain: NSOSStatusErrorDomain, code: -1))
            let deadline = Date().addingTimeInterval(2)
            while rack.debugInstantiationCallbacks < count && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
            assert(rack.debugInstantiationCallbacks == count)
        }
        // Fail each component while the remaining callback is still owned by
        // the previous generation; only the actual failed ID becomes blocked.
        store.choose(1); assert(replies.count == 2)
        replyFailure(); replyFailure()
        store.refreshBlockedAudioUnits(includeCatalog: false)
        assert(store.blockedAudioUnits.map(\.id) == [ids[0]])
        assert(store.blockedAudioUnits[0].name == "Generated recovery instrument 0")
        // Allowing retry changes journal permission only; it does not silently
        // restart audio or alter the selected authored layer/session state.
        let before = store.patch.layers
        assert(store.allowBlockedAudioUnit(ids[0]))
        assert(store.blockedAudioUnits.isEmpty && !store.started && !store.audio.running && store.patch.layers == before)
        store.start(); assert(replies.count == 2)
        // Complete slot zero without a plugin error and reject slot one.
        let count = rack.debugInstantiationCallbacks + 1
        replies.removeFirst()(AVAudioUnitSampler(), nil)
        let deadline = Date().addingTimeInterval(2)
        while rack.debugInstantiationCallbacks < count && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
        assert(rack.debugInstantiationCallbacks == count)
        replyFailure()
        store.refreshBlockedAudioUnits(includeCatalog: false)
        assert(Set(store.blockedAudioUnits.map(\.id)) == [ids[1]])
        assert(store.allowBlockedAudioUnit(ids[0])) // Unblocked identity is a no-op.
        assert(Set(store.blockedAudioUnits.map(\.id)) == [ids[1]] && !store.started)
        assert(store.allowAllBlockedAudioUnits() && store.blockedAudioUnits.isEmpty)
        print("PASS plugin recovery settings: named failures, selective permission, preserved patch state and explicit retry")
    }
}
