import Foundation

@main struct TransactionalImportTests {
    @MainActor static func main() async throws {
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let library=SoundLibrary(url:root.appendingPathComponent("sound-library.json"))
        let a=LibrarySound(id:"first",name:"Personal Edit",collection:"My Sounds",layer:Layer(name:"Pad",instrument:1,gain:0.5))
        var b=a;b.id="second";b.name="Prepared Import"
        try library.write([a]);let original=try library.read()
        var edited=a;edited.name="Edit During Import"
        try library.write([edited]);let editedBytes=try Data(contentsOf:library.url)
        do {try library.commitImport([a,b],replacing:original);assertionFailure("Concurrent edits lost")} catch {}
        assert(try! Data(contentsOf:library.url)==editedBytes)
        do {try library.commitImport([edited,edited],replacing:[edited]);assertionFailure("Duplicate identity accepted")} catch {}
        assert(try! Data(contentsOf:library.url)==editedBytes)
        try library.commitImport([edited,b],replacing:[edited])
        assert(try! library.read()==[edited,b])
        let before=try Data(contentsOf:library.url),store=PerformanceStore()
        let folder=root.appendingPathComponent("Source")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try Data("unsupported EXS".utf8).write(to:folder.appendingPathComponent("Broken.exs"))
        store.importSamplerLibrary(folder);store.cancelLibraryImport()
        for _ in 0..<100 where store.libraryImportBusy {try await Task.sleep(nanoseconds:10_000_000)}
        assert(!store.libraryImportBusy && store.libraryImportProgress?.contains("cancelled")==true)
        assert(try! Data(contentsOf:library.url)==before)
        store.importSamplerLibrary(folder)
        for _ in 0..<100 where store.libraryImportBusy {try await Task.sleep(nanoseconds:10_000_000)}
        assert(!store.libraryImportBusy && store.libraryImportProgress?.contains("not committed")==true)
        assert(try! Data(contentsOf:library.url)==before)
        print("PASS: import commit preserves concurrent edits; duplicates, cancellation and invalid conversion leave catalog bytes unchanged")
    }
}
