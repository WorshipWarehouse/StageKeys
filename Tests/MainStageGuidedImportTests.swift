import Foundation

@main struct MainStageGuidedImportTests {
    @MainActor static func main()async throws {
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let patch=root.appendingPathComponent("Synthetic.patch")
        let instrument=try TestFixtures.exs(in:patch)
        let sample=patch.appendingPathComponent("Fixture.wav"),sampleHash=try AssetDigest.sha256(sample),instrumentHash=try AssetDigest.sha256(instrument)
        let strip=TestFixtures.mainStageStrip(["Fixture.exs"])
        try strip.write(to:patch.appendingPathComponent("First.cst"));try strip.write(to:patch.appendingPathComponent("Second.cst"))
        try TestFixtures.mainStageStrip(["Missing.exs"]).write(to:patch.appendingPathComponent("Missing.cst"))
        let document:[String:Any]=["channels":[["Filename":"First.cst","Channel_name":"First","volume":1_509_949_440],["Filename":"Second.cst","Channel_name":"Second","volume":535_750_245],["Filename":"Missing.cst","Channel_name":"Missing"]]]
        let bytes=try PropertyListSerialization.data(fromPropertyList:document,format:.binary,options:0)
        try bytes.write(to:patch.appendingPathComponent("data.plist"))
        let store=PerformanceStore()
        func wait()async throws{for _ in 0..<1500 where store.libraryImportBusy{try await Task.sleep(nanoseconds:10_000_000)};assert(!store.libraryImportBusy)}
        store.importMainStageAutomatically(patch,locations:[.init(instruments:patch,samples:patch,label:"Synthetic source")])
        try await wait()
        assert(store.mainStageOutcomes.map(\.state)==[.converted,.converted,.needsSamples],store.libraryImportProgress ?? "No outcomes")
        assert(store.librarySounds.filter{$0.id.hasPrefix("mainstage-channel-")}.count==2)
        assert(store.mainStageSearches.first?.detail.contains("1 matching")==true)
        store.assembleConvertedMainStagePatch(readyOnly:true)
        assert(store.patch.layers[0].name=="First" && store.patch.layers[1].name=="Second")
        assert(abs(store.patch.layers[1].gain-pow(10,-18.0/20))<0.00001)
        assert(store.patch.conversionNotes?.contains{$0.contains("Not included: Missing")}==true)
        try store.audio.prepareOffline();store.audio.configure(0,store.patch.layers[0]);store.audio.gain(0,0.3,seconds:0);store.audio.master(0.1)
        store.audio.noteOn(key:60,pitch:60,instrument:-1,layer:0,velocity:0.7)
        var energy=0.0
        for _ in 0..<40 {let buffer=try store.audio.offlineBlock();for frame in 0..<Int(buffer.frameLength){let value=Double(buffer.floatChannelData![0][frame]);assert(value.isFinite);energy+=value*value}}
        store.audio.stop();assert(energy>0.001,"Auto-discovered native EXS must play")
        let count=store.librarySounds.count
        store.importMainStageAutomatically(patch,locations:[.init(instruments:patch,samples:patch,label:"Synthetic source")]);try await wait()
        assert(store.librarySounds.count==count && store.mainStageOutcomes[0].state == .duplicate)
        let catalog=root.appendingPathComponent("sound-library.json"),before=try Data(contentsOf:catalog)
        store.importMainStageAutomatically(patch,locations:[.init(instruments:patch,samples:patch,label:"Synthetic source")]);store.cancelLibraryImport();try await wait()
        assert((try! Data(contentsOf:catalog))==before)
        let other=root.appendingPathComponent("Conflicting");_ = try TestFixtures.exs(in:other)
        var conflicting=try Data(contentsOf:other.appendingPathComponent("Fixture.exs"));conflicting.append(0);try conflicting.write(to:other.appendingPathComponent("Fixture.exs"))
        let result=MainStageDiscovery.find(["Fixture.exs"],locations:[.init(instruments:patch,samples:patch,label:"A"),.init(instruments:other,samples:other,label:"B")])
        assert(Set(result.candidates["Fixture.exs"]!.map(\.sha256)).count==2,"Different source bytes must remain ambiguous")
        let sampleAfter=try AssetDigest.sha256(sample),instrumentAfter=try AssetDigest.sha256(instrument)
        assert(sampleAfter==sampleHash && instrumentAfter==instrumentHash && (try! Data(contentsOf:patch.appendingPathComponent("data.plist")))==bytes)
        let rollbackRoot=root.appendingPathComponent("strict-data")
        setenv("STAGEKEYS_DATA_DIR",rollbackRoot.path,1)
        let strict=PerformanceStore();strict.importMainStagePatch(patch);strict.importMainStageSamplers(patch)
        for _ in 0..<1500 where strict.libraryImportBusy {try await Task.sleep(nanoseconds:10_000_000)}
        assert(strict.librarySounds.isEmpty && strict.libraryImportProgress?.contains("not committed")==true)
        for folder in ["Imported Sounds","Original Instruments"] {assert(((try? FileManager.default.contentsOfDirectory(atPath:rollbackRoot.appendingPathComponent(folder).path)) ?? []).isEmpty,"Failed batch left prepared assets")}
        strict.importMainStageSamplers(patch,allowPartial:true)
        let cancellation=Task { @MainActor in
            while strict.libraryImportBusy {
                if strict.mainStageOutcomes.contains(where:{$0.state == .prepared}) {strict.cancelLibraryImport();return}
                await Task.yield()
            }
        }
        for _ in 0..<1500 where strict.libraryImportBusy {try await Task.sleep(nanoseconds:10_000_000)}
        await cancellation.value
        assert(strict.librarySounds.isEmpty && strict.libraryImportProgress?.contains("cancelled")==true)
        for folder in ["Imported Sounds","Original Instruments"] {assert(((try? FileManager.default.contentsOfDirectory(atPath:rollbackRoot.appendingPathComponent(folder).path)) ?? []).isEmpty,"Cancelled batch left prepared assets")}
        setenv("STAGEKEYS_DATA_DIR",root.path,1)
        let modern=try TestFixtures.exs(in:root.appendingPathComponent("Modern"),name:"Modern.exs",modern:true)
        let modernStore=PerformanceStore()
        guard let modernSound=modernStore.importLibrarySound(modern,sampleRoot:modern.deletingLastPathComponent()) else{fatalError(modernStore.message ?? "Modern synthetic EXS failed")}
        assert(modernSound.nativeSampler?.conversionVersion==6)
        let restarted=PerformanceStore();assert(restarted.librarySounds.contains{$0.sound?.fileName==modernSound.fileName})
        print("Golden corpus: original generated legacy and modern EXS; MainStage installed:",FileManager.default.fileExists(atPath:"/Applications/MainStage.app"),"; conversion/playback does not launch MainStage")
        print("PASS: synthetic EXS auto-discovery/playback, partial outcomes, identical-strip channel identity, ready-only assembly, duplicate resume, cancellation, ambiguity and original hashes")
    }
}
