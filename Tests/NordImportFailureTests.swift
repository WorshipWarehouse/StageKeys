import Foundation
import AVFoundation

/// Generated-only transaction evidence; never fills a real disk or touches a user library.
@main struct NordImportFailureTests {
    @MainActor static func main() async throws {
        let manager=FileManager.default
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        try manager.createDirectory(at:root,withIntermediateDirectories:true)
        let source=root.appendingPathComponent("Generated.npno"),original=TestFixtures.nordPiano()
        try original.write(to:source)
        let preview=try NordNative.preview(original)
        assert(preview.sourceVersion.contains(String(preview.index.report.contentVersion)))
        assert(preview.minimumAssetBytes==preview.pcmBytes+88)
        assert(preview.targetEligibility.contains("Mac") && preview.targetEligibility.contains("has not been verified"))
        let layer=TestFixtures.layer()
        let seed=LibrarySound(id:"existing-personal-sound",name:"Existing Personal Edit",collection:"My Sounds",sound:layer.external,layer:layer)
        let library=SoundLibrary(url:root.appendingPathComponent("sound-library.json"))
        try library.write([seed])
        let store=PerformanceStore();store.setlist=TestFixtures.setlist()
        store.primarySourceID = -2;store.secondarySourceID = -2
        try store.audio.prepareOffline();store.start();defer{store.stopAudio()}
        store.noteOn(60);store.setSustain(true);store.save()
        let rack=store.audio.externalRack!,unit=rack.unit(channel:0)!
        let document=root.appendingPathComponent("setlist.json"),saved=try Data(contentsOf:document)
        let assets=rack.libraryURL
        func inventory()->[String] {manager.enumerator(atPath:assets.path)!.allObjects.compactMap{$0 as? String}.sorted()}
        let initialAssets=inventory()
        var expectedCatalog=try Data(contentsOf:library.url)
        func wait() async throws {
            let deadline=Date().addingTimeInterval(15)
            while store.libraryImportBusy && Date()<deadline {try await Task.sleep(nanoseconds:5_000_000)}
            assert(!store.libraryImportBusy,"Generated import exceeded its bounded wait")
        }
        func unchanged() throws {
            let catalogBytes=try Data(contentsOf:library.url),documentBytes=try Data(contentsOf:document),sourceBytes=try Data(contentsOf:source)
            assert(catalogBytes==expectedCatalog,"A rejected import must preserve prior catalog bytes")
            assert(documentBytes==saved,"Import changed persisted session bytes")
            assert(sourceBytes==original,"Import changed source bytes")
            assert(inventory()==initialAssets,"Failed preparation must remove only its newly owned assets")
            assert(store.audio.running && rack.unit(channel:0) === unit && store.held.contains(60) && store.sustain)
        }
        func attempt(_ fault:@escaping ()throws->Void) async throws {
            store.inspectNordSound(source);try await wait();assert(store.nordImportPreview != nil)
            store.debugNordImportBeforeCommit=fault
            store.importNordSound();try await wait();store.debugNordImportBeforeCommit=nil
            assert(store.libraryImportProgress?.contains("not committed")==true)
            try unchanged()
        }
        // The commit boundary receives an out-of-space error; no real disk is filled.
        try await attempt {throw CocoaError(.fileWriteOutOfSpace)}
        try await attempt {store.cancelLibraryImport()}
        // Actual filesystem failure during catalog previous-copy rotation.
        let previous=RecoverableSessionFile.previous(library.url)
        try await attempt {try manager.createDirectory(at:previous,withIntermediateDirectories:false)}
        try manager.removeItem(at:previous)
        // A concurrent edit must win over an import's stale catalog snapshot.
        try await attempt {
            var edited=seed;edited.name="Edit made during preparation"
            try library.write([edited]);expectedCatalog=try Data(contentsOf:library.url)
        }
        let editedCatalog=try library.read()
        assert(editedCatalog.first?.name=="Edit made during preparation")
        // Valid container/index but unsupported audio block: fail after inspection.
        var bad=original;bad[preview.index.strokes[0].offset+1]=31
        var crc:UInt32=0xffffffff
        for byte in bad.dropFirst(44) {crc ^= UInt32(byte);for _ in 0..<8 {crc=(crc&1 != 0) ? (crc>>1)^0xedb88320:crc>>1}}
        crc ^= 0xffffffff;for i in 0..<4 {bad[24+i]=UInt8(truncatingIfNeeded:crc>>(i*8))}
        _ = try NordNative.preview(bad)
        let corrupt=root.appendingPathComponent("Generated-invalid-codec.npno");try bad.write(to:corrupt)
        store.inspectNordSound(corrupt);try await wait();assert(store.nordImportPreview != nil)
        store.importNordSound();try await wait();try unchanged()
        let truncated=root.appendingPathComponent("Generated-truncated.npno");try Data(original.prefix(30)).write(to:truncated)
        store.inspectNordSound(truncated);try await wait();assert(store.nordImportPreview==nil);try unchanged()
        store.inspectNordSound(source);try await wait();store.discardNordImport()
        assert(store.nordImportPreview==nil);try unchanged()
        // Retrying after the failed writes succeeds without replacing the edited entry.
        store.inspectNordSound(source);try await wait();store.importNordSound();try await wait()
        let installed=try library.read()
        assert(installed.count==2 && installed.first?.name=="Edit made during preparation")
        assert(installed.last?.id==preview.identity && store.audio.running && rack.unit(channel:0) === unit)
        let finalDocument=try Data(contentsOf:document),finalSource=try Data(contentsOf:source)
        assert(finalDocument==saved && finalSource==original)
        print("PASS Nord import failure: storage/cancel/real catalog-write/codec/corrupt/discard/concurrent-edit rollback, live audio/ownership/bytes, and successful retry")
    }
}
