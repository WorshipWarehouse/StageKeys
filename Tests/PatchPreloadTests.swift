import Foundation

/// The bounded preload window from #109: counts, nearest-first ordering,
/// clamping at the setlist edges, capacity, eviction by recomputation and
/// persistence. No warm audio exists yet, so these assertions bound the window
/// arithmetic only; they say nothing about load time or memory.
@main struct PatchPreloadTests {
    static func main() throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let settingsURL = root.appendingPathComponent("settings.json")
        let store = PerformanceStore()
        var fixture = TestFixtures.setlist()
        let template = fixture.patches[0]
        fixture.patches = (0..<9).map { _ in template.duplicate() }
        store.setlist = fixture
        let count = fixture.patches.count
        assert(store.preloadPrevious == 0 && store.preloadNext == 0, "Preloading is off by default")
        assert(store.preloadWindow.isEmpty, "No window is covered while both counts are 0")
        assert(store.preloadWindowIndices(around: 3, previous: 0, next: 0).isEmpty)

        // Nearest-first: previous before next at the same distance.
        assert(store.preloadWindowIndices(around: 3, previous: 2, next: 2) == [2, 4, 1, 5])
        assert(store.preloadWindowIndices(around: 3, previous: 3, next: 1) == [2, 4, 1, 0])
        // Clamped, not wrapped: the first patch reaches forward only, the last
        // patch reaches backward only.
        assert(store.preloadWindowIndices(around: 0, previous: 2, next: 2) == [1, 2])
        assert(store.preloadWindowIndices(around: count - 1, previous: 2, next: 2) == [count - 2, count - 3])
        // The active patch is never warmed, and an index appears once.
        let interior = store.preloadWindowIndices(around: 4, previous: 4, next: 4)
        assert(!interior.contains(4) && Set(interior).count == interior.count)
        // Capacity is bounded even when a caller asks for more than the limit.
        assert(interior.count == 8, "4 per direction is the hard bound")
        assert(store.preloadWindowIndices(around: 6, previous: 9, next: 9).count <= 8,
               "Counts above the per-direction limit cannot widen the window")
        assert(store.preloadWindowIndices(around: 6, previous: -2, next: -2).isEmpty,
               "Negative counts cannot widen the window")
        assert(store.preloadWindowIndices(around: -1, previous: 2, next: 2).isEmpty)
        assert(store.preloadWindowIndices(around: count, previous: 2, next: 2).isEmpty)

        // Selecting a patch recomputes the window; shrinking the counts evicts
        // the indices that left it.
        store.selected = 3
        store.preloadPrevious = 2; store.preloadNext = 2
        assert(store.preloadWindow == [2, 4, 1, 5])
        store.preloadNext = 0
        assert(store.preloadWindow == [2, 1], "Reducing the window evicts forward entries")
        store.selected = 4
        assert(store.preloadWindow == [3, 2], "A new selection recomputes around it")
        assert(store.warmedChannels.isEmpty, "Nothing is warmed while audio is not running")
        // Persistence round trip, including the window that follows the counts.
        store.preloadPrevious = 2; store.preloadNext = 1
        store.save()
        let restored = PerformanceStore()
        assert(restored.preloadPrevious == 2 && restored.preloadNext == 1)
        assert(restored.preloadWindow == restored.preloadWindowIndices(around: restored.selected))

        // Values outside 0...4 are rejected by the settings schema, so an edited
        // file cannot widen the window even though the property is not clamped.
        let saved = try Data(contentsOf: settingsURL)
        var legacy = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
        legacy.removeValue(forKey: "preloadPrevious"); legacy.removeValue(forKey: "preloadNext")
        let decoded = try JSONDecoder().decode(SessionSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        assert(decoded.preloadPrevious == nil && decoded.preloadNext == nil && decoded.validate())
        for value in [-1, 5, 9] {
            var invalid = legacy; invalid["preloadPrevious"] = value
            let over = try JSONDecoder().decode(SessionSettings.self, from: JSONSerialization.data(withJSONObject: invalid))
            assert(!over.validate(), "preloadPrevious \(value) must be rejected")
        }
        for value in [0, 1, 4] {
            var valid = legacy; valid["preloadNext"] = value
            let accepted = try JSONDecoder().decode(SessionSettings.self, from: JSONSerialization.data(withJSONObject: valid))
            assert(accepted.validate(), "preloadNext \(value) must be accepted")
        }

        // A legacy settings file keeps the former behaviour: preloading off.
        try JSONSerialization.data(withJSONObject: legacy).write(to: settingsURL)
        let migrated = PerformanceStore()
        assert(migrated.preloadPrevious == 0 && migrated.preloadNext == 0 && migrated.preloadWindow.isEmpty)
        print("PASS patch preload window: default off, nearest-first clamp, capacity, eviction, persistence and schema bounds")
    }
}
