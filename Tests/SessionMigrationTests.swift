import Foundation
import Darwin

@main struct SessionMigrationTests {
    private static let validateSetlist: (Data) throws -> Void = {
        _ = try JSONDecoder().decode(Setlist.self, from: $0).upgraded()
    }

    private static func legacyV1(_ source: Setlist) throws -> Data {
        var legacy = source
        legacy.version = 1
        for i in legacy.patches.indices {
            legacy.patches[i].layers = Array(legacy.patches[i].layers.prefix(3))
            for j in legacy.patches[i].snapshots.indices {
                legacy.patches[i].snapshots[j].gains = Array(legacy.patches[i].snapshots[j].gains.prefix(3))
                if legacy.patches[i].snapshots[j].sounds != nil {
                    legacy.patches[i].snapshots[j].sounds = Array(legacy.patches[i].snapshots[j].sounds!.prefix(3))
                }
            }
        }
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        var patches = object["patches"] as! [[String: Any]]
        for i in patches.indices {
            for key in ["playIn", "hearIn", "visualMode", "silencePrevious"] { patches[i].removeValue(forKey: key) }
            var layers = patches[i]["layers"] as! [[String: Any]]
            for j in layers.indices {
                for key in ["effects", "pan", "blockSustain", "octaveEffect", "channelSettings", "external", "pluginState", "midiProgram", "midiDestinationID", "midiOutputChannel"] {
                    layers[j].removeValue(forKey: key)
                }
            }
            patches[i]["layers"] = layers
        }
        object["patches"] = patches
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func main() throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let migrationRoot = root.appendingPathComponent("schema-migration", isDirectory: true)
        try FileManager.default.createDirectory(at: migrationRoot, withIntermediateDirectories: true)
        let primary = migrationRoot.appendingPathComponent("setlist.json")
        var old = Setlist()
        old.name = "Legacy session"
        old.patches[0].name = "Legacy patch"
        old.patches[0].layers[0].instrument = 0
        old.patches[0].layers[0].name = "Legacy voice"
        old.patches[0].layers[0].gain = 0.37
        old.patches[0].snapshots = [Snapshot(name: "Legacy snapshot", gains: Array(repeating: 0.37, count: 15))]
        let legacyBytes = try legacyV1(old)
        try legacyBytes.write(to: primary, options: .atomic)
        setenv("STAGEKEYS_DATA_DIR", migrationRoot.path, 1)

        let migratedStore = PerformanceStore()
        assert(!migratedStore.sessionRecoveryRequired)
        assert(migratedStore.setlist.version == 4 && migratedStore.setlist.name == "Legacy session")
        assert(migratedStore.patch.layers.count == 15 && migratedStore.patch.layers[0].gain == 0.37)
        assert(migratedStore.patch.snapshots[0].gains.count == 15)
        migratedStore.save()

        let previous = RecoverableSessionFile.previous(primary)
        let legacyBackup = migrationRoot.appendingPathComponent("setlist-v1-backup.json")
        let migratedBytes = try Data(contentsOf: primary)
        let migrated = try JSONDecoder().decode(Setlist.self, from: migratedBytes)
        assert(migrated.version == 4 && migrated.patches[0].layers.count == 15)
        assert(try! Data(contentsOf: previous) == legacyBytes, "The first migrated save must retain exact legacy source bytes")
        assert(try! Data(contentsOf: legacyBackup) == legacyBytes, "The versioned migration archive must retain exact legacy source bytes")

        let restarted = PerformanceStore()
        assert(!restarted.sessionRecoveryRequired && restarted.setlist.version == 4)
        assert(restarted.setlist.patches[0].id == old.patches[0].id)
        assert(restarted.setlist.patches[0].snapshots[0].gains.count == 15)

        let restoredBytes = try RecoverableSessionFile.restore(primary, validate: validateSetlist)
        assert(restoredBytes == legacyBytes && (try! Data(contentsOf: primary)) == legacyBytes)
        let retainedMigrated = try FileManager.default.contentsOfDirectory(at: migrationRoot, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(".damaged-") }
        assert(retainedMigrated.count == 1 && (try! Data(contentsOf: retainedMigrated[0])) == migratedBytes)
        let rollbackRestart = PerformanceStore()
        assert(!rollbackRestart.sessionRecoveryRequired && rollbackRestart.setlist.version == 4)
        assert(rollbackRestart.setlist.name == "Legacy session")
        rollbackRestart.save()
        rollbackRestart.setlist.name = "Autosaved after migration"
        rollbackRestart.master = 0.43
        rollbackRestart.save()
        let latest = PerformanceStore()
        assert(latest.setlist.version == 4 && latest.setlist.name == "Autosaved after migration")
        assert(latest.master == 0.43, "Autosaved settings must survive restart")
        assert(try! Data(contentsOf: legacyBackup) == legacyBytes, "Later autosaves must not replace the first-migration archive")

        let futureRoot = root.appendingPathComponent("future-schema", isDirectory: true)
        try FileManager.default.createDirectory(at: futureRoot, withIntermediateDirectories: true)
        let futurePrimary = futureRoot.appendingPathComponent("setlist.json")
        var futureSetlist = Setlist()
        futureSetlist.version = 99
        let futureBytes = try JSONEncoder().encode(futureSetlist)
        let goodBackup = try JSONEncoder().encode(Setlist())
        try futureBytes.write(to: futurePrimary, options: .atomic)
        try goodBackup.write(to: RecoverableSessionFile.previous(futurePrimary), options: .atomic)
        setenv("STAGEKEYS_DATA_DIR", futureRoot.path, 1)
        let futureStore = PerformanceStore()
        assert(futureStore.sessionRecoveryRequired)
        futureStore.save()
        assert(try! Data(contentsOf: futurePrimary) == futureBytes)
        assert(try! Data(contentsOf: RecoverableSessionFile.previous(futurePrimary)) == goodBackup)

        let failureRoot = root.appendingPathComponent("atomic-failures", isDirectory: true)
        try FileManager.default.createDirectory(at: failureRoot, withIntermediateDirectories: true)
        let file = failureRoot.appendingPathComponent("setlist.json")
        var current = Setlist()
        current.name = "Last valid primary"
        let currentBytes = try JSONEncoder().encode(current)
        var older = current
        older.name = "Prior valid primary"
        let olderBytes = try JSONEncoder().encode(older)
        var next = current
        next.name = "Interrupted candidate"
        let nextBytes = try JSONEncoder().encode(next)
        try RecoverableSessionFile.write(olderBytes, to: file, validate: validateSetlist)
        try RecoverableSessionFile.write(currentBytes, to: file, validate: validateSetlist)
        let backupBeforeFailure = try Data(contentsOf: RecoverableSessionFile.previous(file))
        try RecoverableSessionFile.write(currentBytes, to: file, validate: validateSetlist)
        assert(try! Data(contentsOf: RecoverableSessionFile.previous(file)) == backupBeforeFailure, "An identical save must not rotate recovery bytes")
        var invalidCandidate = current
        invalidCandidate.version = 99
        do {
            try RecoverableSessionFile.write(try JSONEncoder().encode(invalidCandidate), to: file, validate: validateSetlist)
            assertionFailure("An unsupported candidate schema was accepted")
        } catch {}
        assert(try! Data(contentsOf: file) == currentBytes)
        assert(try! Data(contentsOf: RecoverableSessionFile.previous(file)) == backupBeforeFailure)
        var reachedBackupWrite = false
        do {
            try RecoverableSessionFile.write(nextBytes, to: file, atomicWrite: { _, target in
                if target == RecoverableSessionFile.previous(file) {
                    reachedBackupWrite = true
                    throw CocoaError(.fileWriteNoPermission)
                }
            }, validate: validateSetlist)
            assertionFailure("A failed backup rotation was accepted")
        } catch {
            assert((error as? CocoaError)?.code == .fileWriteNoPermission)
        }
        assert(reachedBackupWrite, "The backup-write failure was not injected")
        assert(try! Data(contentsOf: file) == currentBytes)
        assert(try! Data(contentsOf: RecoverableSessionFile.previous(file)) == backupBeforeFailure)

        let interruptedTemporary = file.appendingPathExtension("interrupted")
        defer { try? FileManager.default.removeItem(at: interruptedTemporary) }
        do {
            try RecoverableSessionFile.write(nextBytes, to: file, atomicWrite: { data, target in
                if target == file {
                    try data.write(to: interruptedTemporary, options: .atomic)
                    throw CocoaError(.fileWriteUnknown)
                }
                try data.write(to: target, options: .atomic)
            }, validate: validateSetlist)
            assertionFailure("An interrupted primary publication was accepted")
        } catch {}
        assert(try! Data(contentsOf: file) == currentBytes, "A failed atomic replacement must retain the last valid primary")
        assert(try! Data(contentsOf: RecoverableSessionFile.previous(file)) == currentBytes)
        assert(try! Data(contentsOf: interruptedTemporary) == nextBytes, "The interruption fixture must contain the unpublished candidate")
        print("PASS: v1 migration, exact-byte rollback, autosave/restart round-trip and future-schema protection")
        print("PASS: backup-write and interrupted primary-publication failures retain valid session bytes")
    }
}
