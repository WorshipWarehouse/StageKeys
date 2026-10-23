import Foundation

@main struct SessionRecoveryTests {
    static func main() throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("setlist.json")
        let encoder = JSONEncoder()
        var first = Setlist(); first.name = "Retained Session"
        var second = first; second.name = "Next Session"
        let original = try encoder.encode(first), next = try encoder.encode(second)
        let validate: (Data) throws -> Void = { _ = try JSONDecoder().decode(Setlist.self, from: $0).upgraded() }
        try RecoverableSessionFile.write(original, to: url, validate: validate)
        try RecoverableSessionFile.write(next, to: url, validate: validate)
        assert(try Data(contentsOf: RecoverableSessionFile.previous(url)) == original)
        let damaged = Data("interrupted json".utf8)
        try damaged.write(to: url)
        do { try RecoverableSessionFile.write(next, to: url, validate: validate); assertionFailure("Corrupt source overwritten") } catch {}
        assert(try Data(contentsOf: url) == damaged)
        assert(try Data(contentsOf: RecoverableSessionFile.previous(url)) == original)
        let store = PerformanceStore()
        assert(store.sessionRecoveryRequired)
        store.save() // Simulates resign-active autosave after an invalid startup load.
        assert(try Data(contentsOf: url) == damaged)
        store.recoverPreviousSession()
        assert(!store.sessionRecoveryRequired && store.setlist.name == "Retained Session")
        assert(try Data(contentsOf: url) == original)
        let archives = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(".damaged-") }
        assert(archives.count == 1 && (try Data(contentsOf: archives[0])) == damaged)
        let settings = root.appendingPathComponent("settings.json")
        try damaged.write(to: settings)
        let settingsStore = PerformanceStore()
        assert(settingsStore.settingsRecoveryRequired)
        settingsStore.save()
        assert(try Data(contentsOf: settings) == damaged)
        print("PASS: validated atomic rotation, corrupt-load autosave protection, explicit recovery and damaged-byte retention")
    }
}
