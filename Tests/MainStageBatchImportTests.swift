import Foundation

/// #85: one import can cover a whole MainStage concert or a folder of patches, and
/// a channel that references several sampler instruments becomes one layer per
/// instrument instead of failing the channel. Synthetic fixtures only.
@main struct MainStageBatchImportTests {
    @MainActor static func main()async throws {
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let concert=root.appendingPathComponent("Synthetic.concert",isDirectory:true)
        try FileManager.default.createDirectory(at:concert,withIntermediateDirectories:true)
        func writePatch(_ name:String)throws->URL {
            let patch=concert.appendingPathComponent(name+".patch",isDirectory:true)
            _ = try TestFixtures.exs(in:patch)
            try TestFixtures.mainStageStrip(["Fixture.exs"]).write(to:patch.appendingPathComponent(name+".cst"))
            let document:[String:Any]=["patch":["engineNode":["name":name]],"channels":[["Filename":name+".cst","Channel_name":name]]]
            try PropertyListSerialization.data(fromPropertyList:document,format:.binary,options:0).write(to:patch.appendingPathComponent("data.plist"))
            return patch
        }
        let alpha=try writePatch("Alpha"),beta=try writePatch("Beta")
        let stripFolder=concert.appendingPathComponent("Strip",isDirectory:true)
        _ = try TestFixtures.exs(in:stripFolder)
        let strip=stripFolder.appendingPathComponent("Strip.cst")
        try TestFixtures.mainStageStrip(["Fixture.exs"]).write(to:strip)
        let notes=concert.appendingPathComponent("Notes.txt")
        try Data("not a MainStage document".utf8).write(to:notes)
        // Selection is bounded and explainable: only patch folders and channel strips.
        let sources=try MainStageBatch.sources(in:concert)
        assert(sources.map(\.lastPathComponent)==["Alpha.patch","Beta.patch","Strip.cst"],sources.map(\.path).joined(separator:", "))
        let betaSources = try MainStageBatch.sources(in:beta)
        assert(betaSources.map(\.lastPathComponent)==["Beta.patch"])
        let stripSources = try MainStageBatch.sources(in:strip)
        assert(stripSources.map(\.lastPathComponent)==["Strip.cst"])
        assert(MainStageBatch.canImport(concert) && MainStageBatch.canImport(alpha) && MainStageBatch.canImport(strip) && !MainStageBatch.canImport(notes))
        for unsupported in [notes,concert.appendingPathComponent("Missing")] {
            do {_ = try MainStageBatch.sources(in:unsupported);assertionFailure("Only MainStage documents, concerts and folders are selected")}catch{}
        }
        // One source at a time: every patch and strip in the selection imports.
        setenv("STAGEKEYS_DATA_DIR",root.appendingPathComponent("batch").path,1)
        let batch=PerformanceStore()
        batch.importMainStageBatch(concert)
        for _ in 0..<3000 {
            if batch.libraryImportProgress?.hasPrefix("Batch import")==true {break}
            try await Task.sleep(nanoseconds:10_000_000)
        }
        assert(batch.libraryImportProgress?.hasPrefix("Batch import")==true,batch.libraryImportProgress ?? "No batch summary")
        assert(batch.libraryImportProgress?.contains("3 of 3 sources imported")==true,batch.libraryImportProgress ?? "")
        assert(batch.librarySounds.filter{$0.id.hasPrefix("mainstage-channel-")}.count==3,"Each selected source contributes its converted channel")
        assert(batch.mainStageOutcomes.allSatisfy{$0.state == .converted},batch.mainStageOutcomes.map(\.state.rawValue).joined(separator:", "))
        // A channel with two sampler references becomes two layers in a stable order.
        setenv("STAGEKEYS_DATA_DIR",root.appendingPathComponent("layered").path,1)
        let layered=PerformanceStore()
        let patch=root.appendingPathComponent("Layered.patch",isDirectory:true)
        _ = try TestFixtures.exs(in:patch)
        _ = try TestFixtures.exs(in:patch,name:"Second.exs")
        try TestFixtures.mainStageStrip(["Fixture.exs","Second.exs"]).write(to:patch.appendingPathComponent("Layered.cst"))
        let document:[String:Any]=["patch":["engineNode":["name":"Layered"]],"channels":[["Filename":"Layered.cst","Channel_name":"Layered"]]]
        try PropertyListSerialization.data(fromPropertyList:document,format:.binary,options:0).write(to:patch.appendingPathComponent("data.plist"))
        layered.importMainStageAutomatically(patch,locations:[.init(instruments:patch,samples:patch,label:"Synthetic layered")])
        for _ in 0..<1500 where layered.libraryImportBusy {try await Task.sleep(nanoseconds:10_000_000)}
        assert(!layered.libraryImportBusy)
        let sounds=layered.librarySounds.filter{$0.id.hasPrefix("mainstage-channel-")}.sorted{($0.sourceInstrumentIndex ?? 0)<($1.sourceInstrumentIndex ?? 0)}
        assert(sounds.count==2,layered.libraryImportProgress ?? "Layered channel did not convert")
        assert(sounds.compactMap(\.sourceInstrumentIndex)==[0,1] && sounds.allSatisfy{$0.sourceChannelIndex==0})
        assert(sounds.map(\.name)==["Layered · Fixture","Layered · Second"],sounds.map(\.name).joined(separator:", "))
        let gains=sounds.compactMap{$0.layer?.gain}
        assert(gains.count==2 && gains[0]>0 && abs(gains[0]-gains[1])<0.000_001,"The channel gain is split evenly across its layers")
        assert(sounds.allSatisfy{sound in sound.conversionNotes?.contains{note in note.contains("split evenly")}==true})
        layered.assembleConvertedMainStagePatch(readyOnly:true)
        assert(layered.patch.layers.prefix(2).map(\.name)==["Layered · Fixture","Layered · Second"],layered.patch.layers.prefix(2).map(\.name).joined(separator:", "))
        assert(layered.patch.conversionNotes?.contains{note in note.contains("split evenly")}==true)
        print("PASS: bounded concert/folder selection, per-source batch import and multi-instrument channel layers with split gain")
    }
}
