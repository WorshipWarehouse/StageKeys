import Foundation

@main struct MainStageBatchImportTests {
    @MainActor static func main() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:root)}
        func makePatch(_ bundle:String,channel:String,instruments:[String])throws->URL {
            let patch=root.appendingPathComponent(bundle+".patch",isDirectory:true)
            try FileManager.default.createDirectory(at:patch,withIntermediateDirectories:true)
            for instrument in instruments{_=try TestFixtures.exs(in:patch,name:instrument)}
            try TestFixtures.mainStageStrip(instruments).write(to:patch.appendingPathComponent("Channel.cst"))
            let document:[String:Any]=["patch":["engineNode":["name":bundle]],"channels":[["Filename":"Channel.cst","Channel_name":channel]]]
            try PropertyListSerialization.data(fromPropertyList:document,format:.binary,options:0).write(to:patch.appendingPathComponent("data.plist"))
            return patch
        }
        let data=root.appendingPathComponent("Data",isDirectory:true)
        setenv("STAGEKEYS_DATA_DIR",data.path,1)
        let store=PerformanceStore()
        func wait()async throws {
            for _ in 0..<2000 where store.libraryImportBusy || store.mainStageBatchBusy {try await Task.sleep(nanoseconds:10_000_000)}
            assert(!store.libraryImportBusy && !store.mainStageBatchBusy)
        }
        let layered=try makePatch("Layered",channel:"Keys",instruments:["One.exs","Two.exs"])
        let oneHash=try AssetDigest.sha256(layered.appendingPathComponent("One.exs")),twoHash=try AssetDigest.sha256(layered.appendingPathComponent("Two.exs"))
        store.importMainStageAutomatically(layered,locations:[.init(instruments:layered,samples:layered,label:"Synthetic layered")])
        try await wait()
        assert(store.mainStageOutcomes.count==1 && store.mainStageOutcomes[0].state == .converted,store.libraryImportProgress ?? "No layered outcome")
        assert(store.mainStageOutcomes[0].soundIDs.count==2)
        let layeredEntries=store.librarySounds.filter{$0.id.hasPrefix("mainstage-channel-")}
        assert(layeredEntries.count==2,store.libraryImportProgress ?? "Layered import did not create two sounds")
        assert(layeredEntries.compactMap(\.mainStageLayerIndex).sorted()==[0,1])
        assert(layeredEntries.map(\.name).sorted()==["Keys · One","Keys · Two"])
        store.assembleConvertedMainStagePatch(readyOnly:true)
        guard let assembled=store.setlist.patches.last,assembled.layers.count>=2 else{fatalError("No layered patch was assembled")}
        assert(assembled.layers[0].name=="Keys · One" && assembled.layers[1].name=="Keys · Two","Deterministic layer order must survive assembly")
        let concert=root.appendingPathComponent("Set.concert",isDirectory:true)
        try FileManager.default.createDirectory(at:concert,withIntermediateDirectories:true)
        for (bundle,instrument) in [("First","First.exs"),("Second","Second.exs")] {
            let patch=try makePatch(bundle,channel:bundle,instruments:[instrument])
            try FileManager.default.moveItem(at:patch,to:concert.appendingPathComponent(bundle+".patch",isDirectory:true))
        }
        let before=store.librarySounds.count
        store.importMainStageAutomatically(concert,locations:[.init(instruments:concert,samples:concert,label:"Synthetic concert")])
        assert(store.mainStageBatchBusy && store.mainStageBatchTotal==2)
        try await wait()
        assert(store.mainStageBatchCompleted==2)
        assert(store.librarySounds.count==before+2,store.libraryImportProgress ?? "Concert batch did not add two sounds")
        assert(store.libraryImportProgress?.contains("Added 2 sounds")==true,store.libraryImportProgress ?? "No batch summary")
        assert(store.libraryImportProgress?.contains("2 patch")==true,store.libraryImportProgress ?? "No batch source count")
        let oneAfter=try AssetDigest.sha256(layered.appendingPathComponent("One.exs"))
        let twoAfter=try AssetDigest.sha256(layered.appendingPathComponent("Two.exs"))
        assert(oneAfter==oneHash && twoAfter==twoHash)
        print("PASS: one MainStage channel with two sampler references becomes two ordered layers; a .concert imports as one bounded batch")
    }
}
