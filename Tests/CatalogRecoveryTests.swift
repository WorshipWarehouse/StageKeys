import Foundation

@main struct CatalogRecoveryTests {
    @MainActor static func main() throws {
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let library=SoundLibrary(url:root.appendingPathComponent("sound-library.json"))
        let sample=root.appendingPathComponent("original.wav")
        try Data("original sample bytes".utf8).write(to:sample)
        let sampleHash=try AssetDigest.sha256(sample)
        let first=LibrarySound(id:"owned",name:"Original",collection:"My Sounds",sound:ExternalSound(kind:.sample,name:"Original",fileName:"original.wav"))
        var second=first;second.name="Personal edit"
        try library.write([first]);try library.write([second])
        let backup=try Data(contentsOf:RecoverableSessionFile.previous(library.url))
        let damaged=Data("interrupted catalog".utf8)
        try damaged.write(to:library.url)
        let store=PerformanceStore()
        assert(store.libraryRecoveryRequired && store.librarySounds.isEmpty)
        store.save()
        do {try library.write([]);fatalError("Failed catalog load overwritten with defaults")} catch {}
        assert((try! Data(contentsOf:library.url))==damaged)
        assert((try! Data(contentsOf:RecoverableSessionFile.previous(library.url)))==backup)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let originalSetlist=try encoder.encode(store.setlist)
        store.recoverPreviousLibrary()
        assert(!store.libraryRecoveryRequired && store.librarySounds==[first])
        let unchangedSetlist=try encoder.encode(store.setlist)
        assert(originalSetlist==unchangedSetlist,"Catalog recovery must not alter the current setlist")
        assert((try! library.read())==[first])
        let retained=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.contains("sound-library.json.damaged-")}
        assert(retained.count==1 && (try! Data(contentsOf:retained[0]))==damaged)
        let hashAfter=try AssetDigest.sha256(sample);assert(hashAfter==sampleHash)

        // Oversized primaries are rejected before decoding, but remain recoverable.
        let handle=try FileHandle(forWritingTo:library.url)
        try handle.truncate(atOffset:16_000_001);try handle.close()
        let largeHash=try AssetDigest.sha256(library.url)
        do {_ = try library.read();fatalError("Oversized catalog read accepted")} catch {}
        do {try library.write([second]);fatalError("Oversized catalog overwritten")} catch {}
        let recovered=try library.recoverPrevious();assert(recovered==[first])
        let archives=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.contains("sound-library.json.damaged-")}
        let hashes=try archives.map{try AssetDigest.sha256($0)}
        assert(hashes.contains(largeHash))

        let linked=SoundLibrary(url:root.appendingPathComponent("linked.json"))
        try FileManager.default.createSymbolicLink(at:linked.url,withDestinationURL:library.url)
        do {_ = try linked.read();fatalError("Linked catalog read accepted")} catch {}
        do {try linked.write([second]);fatalError("Linked catalog write accepted")} catch {}
        let dangling=SoundLibrary(url:root.appendingPathComponent("dangling.json"))
        try FileManager.default.createSymbolicLink(at:dangling.url,withDestinationURL:root.appendingPathComponent("absent.json"))
        do {_ = try dangling.read();fatalError("Dangling catalog treated as empty")} catch {}
        do {try dangling.write([]);fatalError("Dangling catalog overwritten")} catch {}
        try damaged.write(to:RecoverableSessionFile.previous(library.url))
        let current=try Data(contentsOf:library.url)
        do {_ = try library.recoverPrevious();fatalError("Invalid backup restored")} catch {}
        assert((try! Data(contentsOf:library.url))==current)
        print("PASS: catalog backup rotation, failed-load write protection, explicit store recovery, original hashes, bounded loads and unsafe/invalid file refusal")
    }
}
