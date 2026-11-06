import Foundation

@main struct SetlistTemplateTests {
    static func main() throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let store = PerformanceStore(); store.setlist = TestFixtures.setlist()
        store.setlist.name = "Generated Stage Template"
        try store.audio.prepareOffline(); store.start(); store.choose(1); defer { store.stopAudio() }
        store.captureSnapshot(0); store.save()
        let library = try SetlistLibrary(root: root.appendingPathComponent("Setlists"))
        let originalID = store.currentSetlistID!, selected = store.selected, snapshot = store.activeSnapshot
        let document = root.appendingPathComponent("setlist.json")
        let sourcePath = library.root.appendingPathComponent(originalID.uuidString + ".json")
        let sourceBytes = try Data(contentsOf: sourcePath), documentBytes = try Data(contentsOf: document)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let original = try encoder.encode(store.setlist)
        store.noteOn(60); store.setSustain(true); store.patchLock = true
        let id = store.createLocalSetlistFromTemplate(originalID, name: "  Next Service  ")!
        assert(id != originalID && store.currentSetlistID == originalID && store.selected == selected && store.activeSnapshot == snapshot)
        assert(store.held.contains(60) && store.sustain && store.started && store.audio.running && store.patchLock)
        assert(try! encoder.encode(store.setlist) == original)
        assert(try! Data(contentsOf: sourcePath) == sourceBytes)
        assert(try! Data(contentsOf: document) == documentBytes)
        let source = try library.load(id: originalID)
        var copy = try library.load(id: id)
        assert(copy.name == "Next Service")
        assert(Set(copy.patches.map(\.id)).isDisjoint(with: Set(source.patches.map(\.id))))
        var normalized = copy; normalized.name = source.name
        for index in source.patches.indices {
            assert(Set(copy.patches[index].layers.map(\.id)).isDisjoint(with: Set(source.patches[index].layers.map(\.id))))
            assert(Set(copy.patches[index].snapshots.map(\.id)).isDisjoint(with: Set(source.patches[index].snapshots.map(\.id))))
            normalized.patches[index].id = source.patches[index].id
            for layer in source.patches[index].layers.indices { normalized.patches[index].layers[layer].id = source.patches[index].layers[layer].id }
            for scene in source.patches[index].snapshots.indices { normalized.patches[index].snapshots[scene].id = source.patches[index].snapshots[scene].id }
        }
        assert(try! encoder.encode(normalized) == encoder.encode(source), "Only instance identities and the chosen title may change")
        copy.patches[0].layers[0].pan = 0.8
        _ = try library.save(copy, id: id)
        assert(try! Data(contentsOf: sourcePath) == sourceBytes)
        let copyBytes = try Data(contentsOf: library.root.appendingPathComponent(id.uuidString + ".json"))
        let inactiveCopyID = store.createLocalSetlistFromTemplate(id, name: "Inactive Source Copy")!
        assert(inactiveCopyID != id && store.currentSetlistID == originalID && store.held.contains(60))
        store.setGain(0, 0.4); store.save()
        assert(try! Data(contentsOf: library.root.appendingPathComponent(id.uuidString + ".json")) == copyBytes)
        var energy = 0.0
        for _ in 0..<32 {
            let buffer = try store.audio.offlineBlock()
            for frame in 0..<Int(buffer.frameLength) { energy += Double(abs(buffer.floatChannelData![0][frame])) }
        }
        assert(energy > 0.01)
        let count = try library.list().entries.count
        for title in ["", " \n ", String(repeating: "x", count: 201)] {
            assert(store.createLocalSetlistFromTemplate(originalID, name: title) == nil)
        }
        assert(store.createLocalSetlistFromTemplate(UUID(), name: "Missing Template") == nil)
        assert(try! library.list().entries.count == count)
        assert(store.currentSetlistID == originalID && store.held.contains(60) && store.sustain)
        let persisted = try library.load(id: id)
        assert(persisted.patches[0].layers[0].pan == 0.8)
        // A failed startup must not turn its fallback document into the active
        // template. A different readable saved source can still be copied safely.
        let goodPrimary = try Data(contentsOf: document)
        let goodLibrary = try Data(contentsOf: sourcePath)
        let damaged = Data("generated corrupt primary".utf8)
        try damaged.write(to: document)
        let blocked = PerformanceStore()
        assert(blocked.sessionRecoveryRequired && blocked.currentSetlistID == originalID)
        assert(blocked.createLocalSetlistFromTemplate(originalID, name: "Blocked Active Copy") == nil)
        assert(try! Data(contentsOf: sourcePath) == goodLibrary)
        let safeCopy = blocked.createLocalSetlistFromTemplate(id, name: "Readable Saved Copy")
        assert(safeCopy != nil && blocked.currentSetlistID == originalID && blocked.sessionRecoveryRequired)
        assert(try! Data(contentsOf: document) == damaged)
        assert(try! Data(contentsOf: sourcePath) == goodLibrary)
        try goodPrimary.write(to: document) // Restore only this disposable test fixture.

        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let c = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let entries = [SetlistLibraryDescriptor(id: c, name: "Zulu", patchCount: 1, modifiedDate: Date(timeIntervalSince1970: 20)),
                       SetlistLibraryDescriptor(id: b, name: "Alpha", patchCount: 1, modifiedDate: Date(timeIntervalSince1970: 10)),
                       SetlistLibraryDescriptor(id: a, name: "Alpha", patchCount: 1, modifiedDate: Date(timeIntervalSince1970: 10))]
        assert(SetlistBrowserOrder.updated.entries(entries, search: "").map(\.id) == [c,a,b])
        assert(SetlistBrowserOrder.name.entries(entries, search: "").map(\.id) == [a,b,c])
        assert(SetlistBrowserOrder.name.entries(entries, search: " ALPHA ").map(\.id) == [a,b])
        assert(SetlistBrowserOrder.updated.entries(entries, search: "missing").isEmpty)
        assert(SetlistBrowserOrder.updated.entries([], search: "").isEmpty)
        assert(SetlistBrowserOrder.recent.entries(entries, search: "", recents: [b, c]).map(\.id) == [b,c,a])
        assert(SetlistBrowserOrder.recent.entries(entries, search: "alpha", recents: [c, b]).map(\.id) == [b,a])
        assert(SetlistBrowserOrder.recent.entries(entries, search: "").map(\.id) == [c,a,b])
        assert(SetlistBrowserOrder.recent.entries(entries, search: "zulu", recents: [a]).map(\.id) == [c])
        // The history is bounded, de-duplicated and tolerant of damaged bytes.
        let recentsURL = root.appendingPathComponent("setlist-recents.json")
        var recents = SetlistRecents().recording(a).recording(b).recording(a)
        assert(recents.ids == [a,b])
        try recents.write(to: recentsURL)
        assert(SetlistRecents.read(recentsURL).ids == [a,b])
        assert(SetlistRecents.read(root.appendingPathComponent("missing-recents.json")).ids.isEmpty)
        recents = recents.removing(a)
        assert(recents.ids == [b] && recents.retaining([a]).ids.isEmpty)
        var bounded = SetlistRecents()
        for value in 0..<25 { bounded = bounded.recording(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!) }
        assert(bounded.ids.count == SetlistRecents.maximum && bounded.ids.first!.uuidString.hasSuffix("000000000024"))
        try Data("damaged history".utf8).write(to: recentsURL)
        assert(SetlistRecents.read(recentsURL).ids.isEmpty)
        try recents.write(to: recentsURL)
        // Failed capacity admission must retain the playing document and copies.
        let existingFiles = try FileManager.default.contentsOfDirectory(at: library.root, includingPropertiesForKeys: nil).filter{$0.pathExtension == "json"}.count
        for _ in existingFiles..<128 { try Data("generated damaged entry".utf8).write(to: library.root.appendingPathComponent(UUID().uuidString + ".json")) }
        assert(store.createLocalSetlistFromTemplate(originalID, name: "Over Capacity") == nil)
        assert(store.currentSetlistID == originalID && store.held.contains(60) && store.sustain && store.audio.running)
        assert(try! Data(contentsOf: library.root.appendingPathComponent(id.uuidString + ".json")) == copyBytes)
        print("PASS local templates: independent identities/metadata, active and inactive sources, retained audio/selection/sustain/lock, failures, capacity, deterministic browser sort/search and bounded recents history")
    }
}
