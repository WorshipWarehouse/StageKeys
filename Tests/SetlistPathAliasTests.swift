import Foundation
@main struct SetlistPathAliasTests {
    static func main() throws {
        let base = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let library = try SetlistLibrary(root: base.appendingPathComponent("Setlists"))
        let saved = try library.save(Setlist())
        let initial = try library.list()
        assert(initial.entries.contains { $0.id == saved.id })
        let loaded = try library.load(id: saved.id)
        assert(loaded.name == Setlist().name)
        let duplicate = try library.duplicate(id: saved.id)
        assert((try! library.list()).entries.count == 2)
        let trashed = try library.delete(id: duplicate.id)
        assert((try! library.list()).entries.count == 1)
        _ = try library.restore(token: trashed.token)
        assert((try! library.list()).entries.count == 2)
        let outside = base.appendingPathComponent("Outside.json")
        try JSONEncoder().encode(Setlist()).write(to: outside)
        let linkID = UUID()
        try FileManager.default.createSymbolicLink(at: library.root.appendingPathComponent(linkID.uuidString + ".json"), withDestinationURL: outside)
        let inventory = try library.list()
        assert(inventory.entries.count == 2 && inventory.issues.count == 1)
        do { _ = try library.load(id: linkID); assertionFailure("Symlink was accepted") } catch {}
        print("PASS: Foundation path aliases preserve listing, load, duplicate and trash/restore while symlink files remain rejected")
    }
}
