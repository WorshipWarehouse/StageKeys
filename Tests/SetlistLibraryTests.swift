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
        // A saved document keeps one validated previous copy, and a damaged primary
        // is preserved beside it before that copy is restored.
        var rotationSource = Setlist()
        rotationSource.name = "Recovery Source"
        var rotation = try library.save(rotationSource)
        assert(!library.hasPreviousCopy(id: rotation.id), "A first save has nothing to rotate")
        rotation = try library.rename(id: rotation.id, name: "Recovery Target")
        assert(library.hasPreviousCopy(id: rotation.id))
        do { _ = try library.recoverPrevious(id: UUID()); assertionFailure("Recovered without a previous copy") }
        catch SetlistLibraryError.noPreviousCopy {}
        try Data("broken json".utf8).write(to: root.appendingPathComponent(rotation.id.uuidString + ".json"))
        let rotationIssue = try library.list().issues.first { $0.fileID == rotation.id }
        assert(rotationIssue?.recoverable == true, "An unreadable document with a previous copy must offer recovery")
        assert(rotationIssue?.message.isEmpty == false, "The issue must carry its reason")
        let recoveredPrevious = try library.recoverPrevious(id: rotation.id)
        assert(recoveredPrevious.id == rotation.id && recoveredPrevious.name == "Recovery Source")
        let restoredDocument = try library.load(id: rotation.id)
        assert(restoredDocument.name == "Recovery Source")
        let rotationFiles = try FileManager.default.contentsOfDirectory(atPath: root.path)
        assert(rotationFiles.contains { $0.hasPrefix(rotation.id.uuidString + ".json.damaged-") },
               "The damaged primary must be retained before restoration")
        // Unreadable bytes are preserved, never rotated over the readable copy.
        try Data("broken json".utf8).write(to: root.appendingPathComponent(rotation.id.uuidString + ".json"))
        _ = try library.save(rotationSource, id: rotation.id)
        let secondRecovery = try library.recoverPrevious(id: rotation.id)
        assert(secondRecovery.name == "Recovery Source")
        // Admission runs before publication: a caller can decode the previous copy
        // and change its mind without the damaged primary being replaced or retained.
        let damagedPrefix = rotation.id.uuidString + ".json.damaged-"
        func damagedCopies() throws -> Int {
            try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(damagedPrefix) }.count
        }
        let damagedBeforePreview = try damagedCopies()
        let damagedPrimary = Data("broken json".utf8)
        try damagedPrimary.write(to: root.appendingPathComponent(rotation.id.uuidString + ".json"))
        let previewed = try library.previous(id: rotation.id)
        assert(previewed.name == secondRecovery.name,"The preview is the copy recovery would restore")
        assert((try! Data(contentsOf: root.appendingPathComponent(rotation.id.uuidString + ".json"))) == damagedPrimary,
               "Decoding the previous copy must not publish it")
        let damagedAtPreview = try damagedCopies()
        assert(damagedAtPreview == damagedBeforePreview,"Previewing must not retain a damaged copy yet")
        do { _ = try library.previous(id: UUID()); assertionFailure("Previewed a missing previous copy") }
        catch SetlistLibraryError.noPreviousCopy {}
        _ = try library.recoverPrevious(id: rotation.id)
        let damagedAfterRecovery = try damagedCopies()
        assert(damagedAfterRecovery == damagedBeforePreview + 1,"Recovery after the preview still retains the damaged bytes")
        // Capacity counts corrupt UUID entries too; none are silently discarded.
        let listing = try library.list()
        var storedDocuments = listing.entries.count + listing.issues.count
        while storedDocuments < 128 {
            try Data("broken json".utf8).write(to: root.appendingPathComponent(UUID().uuidString + ".json"))
            storedDocuments += 1
        }
        do { _ = try library.save(original); assertionFailure("Library capacity exceeded") }
        catch SetlistLibraryError.full {}
        print("PASS setlist save/load, rename, copied identities, corrupt-file isolation, invalid-write protection, recoverable deletion/restore, previous-copy rotation and recovery, symlink refusal, and capacity")
    }
}
