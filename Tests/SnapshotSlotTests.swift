import Foundation
import AVFoundation
@main struct SnapshotSlotTests {
    static func main() throws {
        let store = PerformanceStore()
        try store.audio.prepareOffline()
        store.start()
        store.addPatch("Blank slots")
        assert(store.patch.snapshots.isEmpty)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(store.setlist)
        store.captureSnapshot(-1); store.captureSnapshot(16)
        let afterInvalid = try encoder.encode(store.setlist)
        assert(afterInvalid == before)
        store.captureSnapshot(4)
        assert(store.patch.snapshots.count == 5)
        assert(store.patch.snapshots.prefix(4).allSatisfy(\.isEmptySlot))
        assert(!store.patch.snapshots[4].isEmptySlot)
        let fifth = store.patch.snapshots[4].id
        let active = store.activeSnapshot
        store.recall(store.patch.snapshots[1])
        assert(store.activeSnapshot == active, "Empty slots must not recall zero gains")
        store.captureSnapshot(1)
        assert(store.patch.snapshots[4].id == fifth)
        store.clearSnapshot(1)
        assert(store.patch.snapshots.count == 5 && store.patch.snapshots[1].isEmptySlot)
        assert(store.patch.snapshots[4].id == fifth && store.activeSnapshot == nil)
        store.saveSnapshot()
        assert(!store.patch.snapshots[0].isEmptySlot && store.patch.snapshots.count == 5)
        let recalled = try JSONDecoder().decode(Setlist.self, from: encoder.encode(store.setlist)).upgraded()
        assert(recalled.patches.last!.snapshots[1].isEmptySlot)
        assert(recalled.patches.last!.snapshots[4].id == fifth)
        let legacy = try JSONDecoder().decode(Snapshot.self, from: Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"Legacy\",\"gains\":[0.5]}".utf8))
        assert(!legacy.isEmptySlot)
        store.clearSnapshot(99)
        store.panic()
        print("PASS: sparse capture, stable cleared slots, empty recall guard, index bounds and legacy/session round trips")
    }
}
