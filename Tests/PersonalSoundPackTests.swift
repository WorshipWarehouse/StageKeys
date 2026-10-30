import Foundation

@main struct PersonalSoundPackTests {
    @MainActor static func main()async throws {
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let exs=try TestFixtures.exs(in:root.appendingPathComponent("source"))
        let store=PerformanceStore()
        guard store.importLibrarySound(exs,sampleRoot:exs.deletingLastPathComponent()) != nil,var entry=store.librarySounds.first else{fatalError(store.message ?? "No generated instrument")}
        entry.sourceArchiveID="private-source";entry.originalName="Private source";entry.conversionNotes=["Source at /Users/example/private/file.exs requires review."]
        entry.layer!.gain=0.41;entry.layer!.pan=0.2;entry.layer!.blockSustain=true
        entry.layer!.effects[0]=AudioEffect.factoryDefault(kind:3)
        var gain=AudioEffect.factoryDefault(kind:9);gain.parameters=[-6]
        entry.layer!.importedRack!.effects.append(gain)
        let folder=root.appendingPathComponent("portable-folder")
        try LibraryBackup.write([entry],library:root,to:folder)
        let pack=try LibraryBackup.read(folder)
        assert(pack.sounds.count==1 && pack.sounds[0].sourceArchiveID==nil && pack.sounds[0].originalInstrument==nil && pack.sounds[0].layer?.pluginState==nil)
        assert(pack.sounds[0].layer?.effects==entry.layer?.effects && pack.sounds[0].layer?.importedRack==entry.layer?.importedRack)
        assert(pack.manifest.files.keys.allSatisfy{!$0.hasPrefix("/") && !$0.contains("settings") && !$0.contains("setlist")})
        let catalog=try String(contentsOf:folder.appendingPathComponent("sound-library.json"),encoding:.utf8)
        assert(!catalog.contains("/Users/") && !catalog.contains(root.path))
        let sampleHashes=pack.manifest.files.filter{$0.key.hasPrefix("Imported Sounds/Samples/")}.values
        let originalSampleHash=try AssetDigest.sha256(exs.deletingLastPathComponent().appendingPathComponent("Fixture.wav"))
        assert(sampleHashes.contains(originalSampleHash))
        let archive=root.appendingPathComponent("Personal.stagekeyspack")
        try PersonalSoundArchive.write(folder,to:archive)
        let relocated=root.appendingPathComponent("relocated")
        try FileManager.default.createDirectory(at:relocated,withIntermediateDirectories:true)
        let moved=relocated.appendingPathComponent(archive.lastPathComponent);try FileManager.default.moveItem(at:archive,to:moved)
        let unpacked=try PersonalSoundArchive.unpack(moved,to:root.appendingPathComponent("unpacked"))
        let unpackedPack=try LibraryBackup.read(unpacked)
        assert(unpackedPack.sounds.map(\.id)==[entry.id])
        let target=root.appendingPathComponent("target-data");setenv("STAGEKEYS_DATA_DIR",target.path,1)
        let destination=PerformanceStore(),encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let sessionBefore=try encoder.encode(destination.setlist)
        destination.importLibraryBackup(moved)
        for _ in 0..<1500 where destination.libraryImportBusy {try await Task.sleep(nanoseconds:10_000_000)}
        guard let installed=destination.librarySounds.first,let layer=installed.layer else{fatalError(destination.libraryImportProgress ?? "Pack import failed")}
        assert(layer.effects==entry.layer?.effects && layer.importedRack==entry.layer?.importedRack && layer.gain==0.41 && layer.pan==0.2 && layer.blockSustain)
        let sessionAfter=try encoder.encode(destination.setlist);assert(sessionBefore==sessionAfter)
        func render(_ layer:Layer,in data:URL)throws->Double {
            setenv("STAGEKEYS_DATA_DIR",data.path,1)
            let audio=AudioController();try audio.prepareOffline();defer{audio.stop()}
            audio.configure(0,layer);audio.gain(0,layer.gain,seconds:0);audio.master(0.1);audio.space(0)
            for _ in 0..<10{_ = try audio.offlineBlock()}
            audio.noteOn(key:60,pitch:60,instrument:-1,layer:0,velocity:0.7)
            var energy=0.0
            for _ in 0..<60 {let b=try audio.offlineBlock();for channel in 0..<Int(b.format.channelCount){for frame in 0..<Int(b.frameLength){let v=Double(b.floatChannelData![channel][frame]);assert(v.isFinite);energy+=v*v}}}
            return energy
        }
        let a=try render(entry.layer!,in:root),b=try render(layer,in:target)
        assert(a>0.001 && abs(sqrt(b/a)-1)<0.001,"Relocated native pack changed rendered level/effects")
        setenv("STAGEKEYS_DATA_DIR",target.path,1)
        let restarted=PerformanceStore();assert(restarted.librarySounds.first?.id==entry.id)
        let before=try Data(contentsOf:target.appendingPathComponent("sound-library.json"))
        restarted.importLibraryBackup(moved);for _ in 0..<1500 where restarted.libraryImportBusy{try await Task.sleep(nanoseconds:10_000_000)}
        assert(restarted.librarySounds.count==1)
        restarted.importLibraryBackup(moved);restarted.cancelLibraryImport();for _ in 0..<1500 where restarted.libraryImportBusy{try await Task.sleep(nanoseconds:10_000_000)}
        assert((try! Data(contentsOf:target.appendingPathComponent("sound-library.json")))==before)
        let bytes=try Data(contentsOf:moved)
        for (name,bad) in [("truncated",Data(bytes.dropLast(20))),("trailing",bytes+Data([1])),("altered",Data(bytes.dropLast())+Data([bytes.last! ^ 0xff]))] {
            let file=root.appendingPathComponent(name+".stagekeyspack"),output=root.appendingPathComponent(name+"-out")
            try bad.write(to:file)
            do{_ = try PersonalSoundArchive.unpack(file,to:output);fatalError("Invalid archive accepted")}catch{}
            assert(!FileManager.default.fileExists(atPath:output.path))
        }
        var invalidEntry=entry;invalidEntry.sound=ExternalSound(kind:.audioUnit,name:"AU",component:ExternalAUIdentity(type:0x61756d75,subtype:0x646c7320,manufacturer:0x6170706c,name:"DLS"));invalidEntry.layer?.external=invalidEntry.sound
        assert(LibraryBackup.portabilityIssue(invalidEntry) != nil)
        do{try LibraryBackup.write([invalidEntry],library:root,to:root.appendingPathComponent("invalid-pack"));fatalError("AU snapshots exported")}catch{}
        let originalCatalog=try Data(contentsOf:folder.appendingPathComponent("sound-library.json"))
        try JSONEncoder().encode([invalidEntry]).write(to:folder.appendingPathComponent("sound-library.json"))
        var invalidManifest=pack.manifest;invalidManifest.files["sound-library.json"]=try AssetDigest.sha256(folder.appendingPathComponent("sound-library.json"))
        try JSONEncoder().encode(invalidManifest).write(to:folder.appendingPathComponent("manifest.json"))
        restarted.importLibraryBackup(folder);for _ in 0..<1500 where restarted.libraryImportBusy{try await Task.sleep(nanoseconds:10_000_000)}
        assert(!restarted.portableImportIssues.isEmpty && (try! Data(contentsOf:target.appendingPathComponent("sound-library.json")))==before,"Ineligible entries must be reported before commit")
        try originalCatalog.write(to:folder.appendingPathComponent("sound-library.json"))
        func integer(_ value:UInt64,_ count:Int)->Data{Data((0..<count).map{UInt8(truncatingIfNeeded:value >> ($0*8))})}
        for (name,path,size) in [("escape","../escaped",UInt64(0)),("absolute","/tmp/escaped",0),("oversize","sound-library.json",PersonalSoundArchive.byteLimit+1)] {
            let malicious=PersonalSoundArchive.magic+integer(1,4)+integer(UInt64(path.utf8.count),4)+integer(size,8)+Data(String(repeating:"0",count:64).utf8)+Data(path.utf8)
            let file=root.appendingPathComponent(name+".stagekeyspack"),output=root.appendingPathComponent(name+"-out")
            try malicious.write(to:file)
            do{_ = try PersonalSoundArchive.unpack(file,to:output);fatalError("Unsafe archive accepted")}catch{}
            assert(!FileManager.default.fileExists(atPath:output.path))
        }
        let originalAfter=try AssetDigest.sha256(exs.deletingLastPathComponent().appendingPathComponent("Fixture.wav"));assert(originalAfter==originalSampleHash)
        print("PASS: personal native pack writer/reader, sample hashes, processing and level after relocation/restart, duplicates/cancel, privacy exclusions, truncated/altered/trailing archive refusal")
    }
}
