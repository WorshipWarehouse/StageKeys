import Foundation

@main struct SetlistLibraryTests {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        let library = try SetlistLibrary(root: root)
        let original = Setlist()
        let saved = try library.save(original)
        let renamed = try library.rename(id: saved.id, name: "  Sunday Evening  ")
        assert(renamed.id == saved.id && renamed.name == "Sunday Evening")
        let loaded = try library.load(id: saved.id)
        assert(loaded.patches.map(\.id) == original.patches.map(\.id))
        let copy = try library.duplicate(id: saved.id)
        let duplicated = try library.load(id: copy.id)
        assert(copy.id != saved.id && copy.name == "Sunday Evening Copy")
        assert(duplicated.patches.map(\.name) == loaded.patches.map(\.name))
        assert(Set(duplicated.patches.map(\.id)).isDisjoint(with: Set(loaded.patches.map(\.id))))
        for (left, right) in zip(loaded.patches, duplicated.patches) {
            assert(Set(left.layers.map(\.id)).isDisjoint(with: Set(right.layers.map(\.id))))
            assert(Set(left.snapshots.map(\.id)).isDisjoint(with: Set(right.snapshots.map(\.id))))
            assert(left.layers.map(\.gain) == right.layers.map(\.gain))
            assert(left.snapshots.map(\.name) == right.snapshots.map(\.name))
        }
        let corrupt = root.appendingPathComponent(UUID().uuidString + ".json")
        try Data("broken json".utf8).write(to: corrupt)
        let escaped = root.appendingPathComponent(UUID().uuidString + ".json")
        try FileManager.default.createSymbolicLink(at: escaped, withDestinationURL: corrupt)
        let inventory = try library.list()
        assert(inventory.entries.count == 2 && inventory.issues.count == 2)
        assert(FileManager.default.fileExists(atPath: corrupt.path))
        let corruptData = try Data(contentsOf: corrupt)
        assert(corruptData == Data("broken json".utf8))
        var invalid = loaded
        invalid.patches[0].tempo = 1000
        do { _ = try library.save(invalid, id: saved.id); assertionFailure("Invalid overwrite accepted") }
        catch SetlistError.invalid {}
        let intact = try library.load(id: saved.id)
        assert(intact.patches[0].tempo == loaded.patches[0].tempo)
        let trashed = try library.delete(id: saved.id)
        let remaining = try library.list()
        assert(remaining.entries.map(\.id) == [copy.id])
        let trash = try library.listTrash()
        assert(trash.entries.count == 1 && trash.entries[0].originalID == saved.id)
        let restored = try library.restore(token: trashed.token)
        assert(restored.id == saved.id && restored.name == renamed.name)
        let recovered = try library.load(id: restored.id)
        assert(recovered.patches.map(\.id) == loaded.patches.map(\.id))
        do { _ = try library.restore(token: trashed.token); assertionFailure("Restore overwrote existing setlist") }
        catch SetlistLibraryError.restoreConflict {}
        let stillRecoverable = try library.listTrash()
        assert(stillRecoverable.entries.count == 1)
        // Capacity counts corrupt UUID entries too; none are silently discarded.
        for _ in 4..<128 {
            try Data("broken json".utf8).write(to: root.appendingPathComponent(UUID().uuidString + ".json"))
        }
        do { _ = try library.save(original); assertionFailure("Library capacity exceeded") }
        catch SetlistLibraryError.full {}
        print("PASS setlist save/load, rename, copied identities, corrupt-file isolation, invalid-write protection, recoverable deletion/restore, symlink refusal, and capacity")
    }
}
