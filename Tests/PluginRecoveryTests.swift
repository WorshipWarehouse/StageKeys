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
        let bytes=try Data(contentsOf:file)
        assert(!String(decoding:bytes,as:UTF8.self).contains("pluginState"))
        print("PASS: interrupted/failed loads block retry, explicit recovery clears blocks and concurrent loads retain pending ownership")
    }
}
