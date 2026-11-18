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
        // A capture over a populated slot and a clear both keep the replaced
        // snapshot for one-step undo, scoped to the patch that recorded it.
        store.captureSnapshot(0)
        let captured = try encoder.encode(store.patch.snapshots[0])
        store.setlist.patches[store.selected].layers[0].pan = 0.6
        store.captureSnapshot(0)
        let changed = try encoder.encode(store.patch.snapshots[0])
        assert(changed != captured, "A second capture must record the changed mix")
        assert(store.snapshotUndo != nil, "Capturing over a populated slot must keep an undo")
        store.undoSnapshotChange()
        let restoredCapture = try encoder.encode(store.patch.snapshots[0])
        assert(restoredCapture == captured, "Undo must restore the replaced capture")
        assert(store.snapshotUndo == nil, "A completed undo must be consumed")
        store.clearSnapshot(0)
        assert(store.patch.snapshots[0].isEmptySlot && store.snapshotUndo != nil, "Clearing a populated slot must keep an undo")
        store.undoSnapshotChange()
        let restoredClear = try encoder.encode(store.patch.snapshots[0])
        assert(restoredClear == captured, "Undo must restore a cleared snapshot")
        store.clearSnapshot(0)
        store.addPatch("Undo scope")
        assert(store.snapshotUndo == nil, "A patch change must drop the previous patch's undo")
        store.undoSnapshotChange()
        assert(store.patch.snapshots.allSatisfy(\.isEmptySlot), "A stale undo must not restore into another patch")
        store.clearSnapshot(99)
        // A slot move must drop the pending undo rather than let it overwrite the
        // snapshot that moved into that index.
        store.captureSnapshot(0); store.captureSnapshot(1)
        let slotZero = store.patch.snapshots[0].id, slotOne = store.patch.snapshots[1].id
        store.captureSnapshot(0)
        assert(store.snapshotUndo != nil)
        store.moveSnapshot(1, 0)
        assert(store.patch.snapshots[0].id == slotOne && store.patch.snapshots[1].id == slotZero)
        assert(store.snapshotUndo == nil, "Moving a snapshot slot must drop the pending undo")
        store.undoSnapshotChange()
        assert(store.patch.snapshots[0].id == slotOne, "A dropped undo must not overwrite the moved slot")
        // A layer move reorders the gains the undo carries, so it drops the undo too.
        store.captureSnapshot(0)
        assert(store.snapshotUndo != nil)
        store.moveLayer(0, 1)
        assert(store.snapshotUndo == nil, "Moving a layer must drop the pending snapshot undo")
        // Import/recovery may retain the same patch UUID. Undo must still belong
        // to the outgoing document rather than overwrite its newly loaded copy.
        store.captureSnapshot(0)
        assert(store.snapshotUndo != nil)
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let invalid=root.appendingPathComponent("snapshot-undo-invalid.json")
        try Data("invalid".utf8).write(to:invalid)
        store.load(invalid)
        assert(store.snapshotUndo != nil,"A refused load must keep the current document's undo")
        var incoming=Setlist();incoming.patches=[store.patch]
        incoming.patches[0].snapshots[0].name="Imported same-identity snapshot"
        let imported=root.appendingPathComponent("snapshot-undo-same-patch.json")
        try encoder.encode(incoming).write(to:imported)
        store.load(imported)
        assert(store.patch.id==incoming.patches[0].id)
        assert(store.snapshotUndo==nil,"Replacing a document must invalidate Undo even when patch UUIDs match")
        store.undoSnapshotChange()
        assert(store.patch.snapshots[0].name=="Imported same-identity snapshot")
        store.panic()
        print("PASS: sparse capture, stable cleared slots, empty recall guard, index bounds and legacy/session round trips")
        print("PASS: a capture over a populated slot and a clear each keep one-step undo, scoped to their patch")
    }
}
