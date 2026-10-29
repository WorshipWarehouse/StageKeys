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
        assert(try! Data(contentsOf: RecoverableSessionFile.previous(url)) == original)
        let damaged = Data("interrupted json".utf8)
        try damaged.write(to: url)
        do { try RecoverableSessionFile.write(next, to: url, validate: validate); assertionFailure("Corrupt source overwritten") } catch {}
        assert(try! Data(contentsOf: url) == damaged)
        assert(try! Data(contentsOf: RecoverableSessionFile.previous(url)) == original)
        let store = PerformanceStore()
        assert(store.sessionRecoveryRequired)
        store.save() // Simulates resign-active autosave after an invalid startup load.
        assert(try! Data(contentsOf: url) == damaged)
        store.recoverPreviousSession()
        assert(!store.sessionRecoveryRequired && store.setlist.name == "Retained Session")
        assert(try! Data(contentsOf: url) == original)
        let archives = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(".damaged-") }
        assert(archives.count == 1 && (try! Data(contentsOf: archives[0])) == damaged)
        let settings = root.appendingPathComponent("settings.json")
        try damaged.write(to: settings)
        let settingsStore = PerformanceStore()
        assert(settingsStore.settingsRecoveryRequired)
        settingsStore.save()
        assert(try! Data(contentsOf: settings) == damaged)
        let oversizedRoot=root.appendingPathComponent("oversized")
        try FileManager.default.createDirectory(at:oversizedRoot,withIntermediateDirectories:true)
        let oversized=oversizedRoot.appendingPathComponent("setlist.json")
        try original.write(to:RecoverableSessionFile.previous(oversized))
        FileManager.default.createFile(atPath:oversized.path,contents:nil)
        let handle=try FileHandle(forWritingTo:oversized)
        try handle.write(contentsOf:Data("damaged start".utf8))
        try handle.truncate(atOffset:64_000_001)
        try handle.seek(toOffset:64_000_000)
        try handle.write(contentsOf:Data([0x7f]));try handle.close()
        let oversizedHash=try AssetDigest.sha256(oversized)
        do {_ = try RecoverableSessionFile.read(oversized);assertionFailure("Oversized normal load accepted")} catch {}
        let restored=try RecoverableSessionFile.restore(oversized,validate:validate)
        assert(restored==original && (try! Data(contentsOf:oversized))==original)
        let retained=try FileManager.default.contentsOfDirectory(at:oversizedRoot,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.contains(".damaged-")}
        assert(retained.count==1)
        let retainedHash=try AssetDigest.sha256(retained[0])
        assert(retainedHash==oversizedHash,"Oversized damaged bytes must be preserved exactly")
        assert((try! Data(contentsOf:RecoverableSessionFile.previous(oversized)))==original)

        // A valid recovery file is not permission to follow an unsafe primary.
        let linked=oversizedRoot.appendingPathComponent("linked.json")
        try original.write(to:RecoverableSessionFile.previous(linked))
        try FileManager.default.createSymbolicLink(at:linked,withDestinationURL:oversized)
        do {_ = try RecoverableSessionFile.restore(linked,validate:validate);assertionFailure("Linked primary restored")} catch {}
        assert((try! linked.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink==true)
        assert((try! Data(contentsOf:oversized))==original)
        let dangling=oversizedRoot.appendingPathComponent("dangling.json")
        try original.write(to:RecoverableSessionFile.previous(dangling))
        try FileManager.default.createSymbolicLink(at:dangling,withDestinationURL:oversizedRoot.appendingPathComponent("missing.json"))
        do {_ = try RecoverableSessionFile.restore(dangling,validate:validate);assertionFailure("Dangling linked primary restored")} catch {}
        assert((try! dangling.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink==true)
        let invalidBackup=oversizedRoot.appendingPathComponent("invalid-backup.json")
        try damaged.write(to:invalidBackup);try damaged.write(to:RecoverableSessionFile.previous(invalidBackup))
        do {_ = try RecoverableSessionFile.restore(invalidBackup,validate:validate);assertionFailure("Invalid backup accepted")} catch {}
        assert((try! Data(contentsOf:invalidBackup))==damaged)
        print("PASS: validated atomic rotation, corrupt-load autosave protection, explicit recovery and damaged-byte retention")
        print("PASS: oversized-session recovery preserves original hashes and backup, rejects unsafe primary and invalid backup")
    }
}
