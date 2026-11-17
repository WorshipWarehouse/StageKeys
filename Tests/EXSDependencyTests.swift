import Foundation

/// Validates an authorized installed EXS map without constructing an Audio Unit.
/// Private source paths are supplied only through the environment and never logged.
@main struct EXSDependencyTests {
    static func main() throws {
        let environment=ProcessInfo.processInfo.environment
        guard let source=environment["STAGEKEYS_EXS_FIXTURE"],let root=environment["STAGEKEYS_EXS_ROOT"] else {
            print("SKIP EXS dependency test: provide an installed EXS and its authorized sample root")
            return
        }
        let manifest=try EXSNative.validateSampleReferences(URL(fileURLWithPath:source),sampleRoot:URL(fileURLWithPath:root))
        assert(manifest.count>0 && manifest.sha256.count==64,"A playable EXS must resolve an identified sample manifest")
        let empty=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:empty,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:empty)}
        do {
            _ = try EXSNative.validateSampleReferences(URL(fileURLWithPath:source),sampleRoot:empty)
            assertionFailure("Dependency validation escaped the authorized sample root")
        } catch {}
        print("PASS: EXS dependency preflight resolved \(manifest.count) content-identified original sample reference(s) without constructing a sampler")
    }
}
