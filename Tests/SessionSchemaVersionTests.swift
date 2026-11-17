import Foundation
import Darwin

@main struct SessionSchemaVersionTests {
    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        fatalError(message)
    }

    private static func fixture(version: Int) throws -> Data {
        var setlist = Setlist()
        setlist.version = version
        return try JSONEncoder().encode(setlist)
    }

    /// A legacy-shaped document: three filled slots and matching snapshot gains.
    private static func legacyFixture(version: Int) throws -> Data {
        var setlist = Setlist()
        setlist.version = version
        for i in setlist.patches.indices {
            setlist.patches[i].layers = Array(setlist.patches[i].layers.prefix(3))
            for j in setlist.patches[i].snapshots.indices {
                setlist.patches[i].snapshots[j].gains = Array(setlist.patches[i].snapshots[j].gains.prefix(3))
                if setlist.patches[i].snapshots[j].sounds != nil {
                    setlist.patches[i].snapshots[j].sounds = Array(setlist.patches[i].snapshots[j].sounds!.prefix(3))
                }
            }
        }
        return try JSONEncoder().encode(setlist)
    }

    private static func refusal(_ data: Data) -> SetlistError? {
        do {
            _ = try JSONDecoder().decode(Setlist.self, from: data).upgraded()
            return nil
        } catch let error as SetlistError {
            return error
        } catch {
            fail("A schema problem surfaced as \(error) instead of a SetlistError")
        }
    }

    static func main() throws {
        let envRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let root = envRoot.appendingPathComponent("session-schema", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        assert(SetlistSchema.supported.lowerBound == 1 && SetlistSchema.supported.upperBound == 4
               && Setlist().version == SetlistSchema.current,
               "The schema boundary must name the versions this build reads")

        // Every supported schema decodes, validates and migrates to the current one.
        for version in SetlistSchema.supported {
            let decoded = try JSONDecoder().decode(Setlist.self, from: try fixture(version: version))
            let migrated = try decoded.upgraded()
            assert(migrated.version == SetlistSchema.current,
                   "schema \(version) did not migrate to \(SetlistSchema.current)")
            assert(migrated.patches.allSatisfy { $0.layers.count == 15 },
                   "schema \(version) must keep the fifteen playable slots")
        }
        // A legacy document with fewer slots is padded, not rejected or truncated.
        for version in [1, 2, 3] {
            let migrated = try JSONDecoder().decode(Setlist.self, from: try legacyFixture(version: version)).upgraded()
            assert(migrated.version == SetlistSchema.current)
            assert(migrated.patches[0].layers.count == 15 && migrated.patches[0].snapshots[0].gains.count == 15,
                   "schema \(version) did not pad layers and snapshot gains to fifteen slots")
        }

        // A newer schema names itself instead of being reported as damage.
        for newer in [SetlistSchema.current + 1, 99] {
            guard let error = refusal(try fixture(version: newer)) else {
                fail("schema \(newer) was accepted by a build that reads \(SetlistSchema.supported)")
            }
            guard case let .unsupportedVersion(saved, supported) = error, saved == newer,
                  supported == SetlistSchema.supported else {
                fail("schema \(newer) was refused as \(error) instead of unsupportedVersion")
            }
            assert(error.localizedDescription.contains("newer StageKeys version"),
                   "A newer session must say so: \(error.localizedDescription)")
            assert(error.localizedDescription.contains("left unchanged"),
                   "A refused session must state that its files were not changed")
        }
        // Below the oldest supported schema the message must not claim "newer".
        guard let old = refusal(try fixture(version: 0)), case let .unsupportedVersion(saved, _) = old,
              saved == 0 else { fail("schema 0 was not refused as an unsupported version") }
        assert(old.localizedDescription.contains("does not read") && !old.localizedDescription.contains("newer"),
               "An unreadable old schema must not be described as newer: \(old.localizedDescription)")
        // Real damage still reports as invalid, so the two cases stay distinct.
        let encoded = try fixture(version: 4)
        var emptied = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        emptied["patches"] = []
        let damagedDocument = try JSONSerialization.data(withJSONObject: emptied)
        assert(refusal(damagedDocument) == .invalid,
               "A damaged document must stay invalid rather than look like a version problem")

        // Store: a newer session stays on disk and is never downgraded by recovery.
        let newerRoot = root.appendingPathComponent("newer-schema", isDirectory: true)
        try FileManager.default.createDirectory(at: newerRoot, withIntermediateDirectories: true)
        let newerPrimary = newerRoot.appendingPathComponent("setlist.json")
        let newerBytes = try fixture(version: SetlistSchema.current + 1)
        var good = Setlist()
        good.name = "Last good copy"
        let goodBytes = try JSONEncoder().encode(good)
        try newerBytes.write(to: newerPrimary, options: .atomic)
        try goodBytes.write(to: RecoverableSessionFile.previous(newerPrimary), options: .atomic)
        setenv("STAGEKEYS_DATA_DIR", newerRoot.path, 1)
        let newerStore = PerformanceStore()
        assert(newerStore.sessionRecoveryRequired && newerStore.sessionSavedByNewerVersion,
               "A newer session must block automatic saves and be recognised as newer")
        assert(newerStore.message?.contains("newer StageKeys version") == true,
               "The load message must name the newer session: \(newerStore.message ?? "nil")")
        newerStore.recoverPreviousSession()
        let primaryAfterRecovery = try Data(contentsOf: newerPrimary)
        let previousAfterRecovery = try Data(contentsOf: RecoverableSessionFile.previous(newerPrimary))
        assert(primaryAfterRecovery == newerBytes,
               "Recovery must not replace a session saved by a newer StageKeys version")
        assert(previousAfterRecovery == goodBytes,
               "Recovery must leave the previous copy unchanged when it refuses")
        assert(newerStore.message?.contains("newer StageKeys version") == true,
               "The refusal must explain why recovery was not performed")
        newerStore.save()
        let primaryAfterSave = try Data(contentsOf: newerPrimary)
        assert(primaryAfterSave == newerBytes,
               "Automatic saves must not overwrite a newer-schema session")

        // Store: a damaged session keeps the existing recovery path.
        let damagedRoot = root.appendingPathComponent("damaged-session", isDirectory: true)
        try FileManager.default.createDirectory(at: damagedRoot, withIntermediateDirectories: true)
        let damagedPrimary = damagedRoot.appendingPathComponent("setlist.json")
        try Data("{\"version\":4,\"patches\":".utf8).write(to: damagedPrimary, options: .atomic)
        try goodBytes.write(to: RecoverableSessionFile.previous(damagedPrimary), options: .atomic)
        setenv("STAGEKEYS_DATA_DIR", damagedRoot.path, 1)
        let damagedStore = PerformanceStore()
        assert(damagedStore.sessionRecoveryRequired && !damagedStore.sessionSavedByNewerVersion,
               "Damage must not be classified as a newer schema")
        damagedStore.recoverPreviousSession()
        let recovered = try JSONDecoder().decode(Setlist.self, from: Data(contentsOf: damagedPrimary))
        assert(recovered.version == SetlistSchema.current,
               "Explicit recovery must still restore the previous copy over a damaged session")
        assert(!damagedStore.sessionRecoveryRequired)

        print("PASS: schema \(SetlistSchema.supported) migrate on load, a newer session is refused by name, "
              + "its bytes survive recovery and autosave, and a damaged session keeps the recovery path")
    }
}
