import Foundation

@main struct PluginRecoveryTests {
    static func main() throws {
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let file=root.appendingPathComponent("recovery.json")
        let journal=try PluginLoadRecovery(url:file)
        try journal.begin("crashed-load")
        let restarted=try PluginLoadRecovery(url:file)
        assert(restarted.isBlocked("crashed-load"))
        do {try restarted.begin("crashed-load");assertionFailure("Interrupted load retried automatically")} catch {}
        try restarted.allowBlockedLoads();try restarted.begin("crashed-load")
        try restarted.finish("crashed-load",failed:false)
        let clean=try PluginLoadRecovery(url:file);assert(!clean.isBlocked("crashed-load"))
        try clean.begin("timeout");try clean.finish("timeout",failed:true)
        let failed=try PluginLoadRecovery(url:file);assert(failed.isBlocked("timeout"))
        try failed.begin("concurrent");try failed.begin("concurrent")
        try failed.finish("concurrent",failed:false)
        let interrupted=try PluginLoadRecovery(url:file);assert(interrupted.isBlocked("concurrent"))
        // Selective permission changes preserve other blocked components and
        // refuse to clear blocks while the same component is still pending.
        try interrupted.begin("another-failure"); try interrupted.finish("another-failure", failed: true)
        try interrupted.allowBlockedLoad("timeout")
        assert(!interrupted.isBlocked("timeout") && interrupted.isBlocked("concurrent") && interrupted.isBlocked("another-failure"))
        let selective = try PluginLoadRecovery(url: file)
        assert(!selective.isBlocked("timeout") && selective.isBlocked("another-failure"))
        try selective.begin("overlap"); try selective.begin("overlap")
        try selective.finish("overlap", failed: true)
        do { try selective.allowBlockedLoad("overlap"); assertionFailure("Pending blocked component must not be retried") } catch {}
        do { try selective.allowBlockedLoads(); assertionFailure("Global recovery must not race pending loads") } catch {}
        try selective.finish("overlap", failed: false)
        try selective.allowBlockedLoad("overlap")
        assert(!selective.isBlocked("overlap") && selective.isBlocked("another-failure"))

        // Refuse writes with a generated directory at the journal path. A
        // failed unblock must change neither in-memory blocks nor stored bytes.
        let durable = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        do { try selective.allowBlockedLoad("another-failure"); assertionFailure("Expected failed persistence") } catch {}
        assert(selective.isBlocked("another-failure"))
        do { try selective.begin("new-load"); assertionFailure("Persistence failure must fail closed") } catch {}
        assert(!selective.isLoading("new-load"))
        try FileManager.default.removeItem(at: file); try durable.write(to: file)
        let restored = try PluginLoadRecovery(url: file)
        assert(restored.isBlocked("another-failure"))
        try restored.allowBlockedLoad("another-failure")
        assert(!restored.isBlocked("another-failure") && restored.isBlocked("concurrent"))

        // A failed begin must not leave a phantom pending count in memory.
        let beginFile = root.appendingPathComponent("failed-begin.json")
        let beginJournal = try PluginLoadRecovery(url: beginFile)
        try FileManager.default.removeItem(at: beginFile)
        try FileManager.default.createDirectory(at: beginFile, withIntermediateDirectories: false)
        do { try beginJournal.begin("generated"); assertionFailure("Expected failed begin") } catch {}
        assert(!beginJournal.isLoading("generated"))
        // Failed finish retains pending ownership for conservative restart
        // recovery, and denies new attempts until the journal is reopened.
        let finishFile = root.appendingPathComponent("failed-finish.json")
        let finishJournal = try PluginLoadRecovery(url: finishFile)
        try finishJournal.begin("generated")
        let pendingBytes = try Data(contentsOf: finishFile)
        try FileManager.default.removeItem(at: finishFile)
        try FileManager.default.createDirectory(at: finishFile, withIntermediateDirectories: false)
        do { try finishJournal.finish("generated", failed: true); assertionFailure("Expected failed finish") } catch {}
        assert(finishJournal.isLoading("generated"))
        do { try finishJournal.begin("other"); assertionFailure("Unrecorded completion must fail closed") } catch {}
        try FileManager.default.removeItem(at: finishFile); try pendingBytes.write(to: finishFile)
        let reopened = try PluginLoadRecovery(url: finishFile)
        assert(reopened.isBlocked("generated") && !reopened.isLoading("generated"))
        let corruptFile = root.appendingPathComponent("corrupt-recovery.json")
        let corrupt = Data("generated invalid journal".utf8); try corrupt.write(to: corruptFile)
        do { _ = try PluginLoadRecovery(url: corruptFile); assertionFailure("Corrupt journal was silently cleared") } catch {}
        assert((try! Data(contentsOf: corruptFile)) == corrupt)
        let bytes=try Data(contentsOf:file)
        assert(!String(decoding:bytes,as:UTF8.self).contains("pluginState"))
        print("PASS: interrupted/failed loads block retry, explicit recovery clears blocks and concurrent loads retain pending ownership")
    }
}
