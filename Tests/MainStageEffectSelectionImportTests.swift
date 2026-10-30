import Foundation

@main struct MainStageEffectSelectionImportTests {
    @MainActor static func main()async throws {
        func device(_ name:String,_ values:[Float])->Data {
            let size=208+values.count*4
            var data=Data(repeating:0,count:size+36)
            data.replaceSubrange(0..<4,with:Data("UCuA".utf8))
            for i in 0..<4{data[28+i]=UInt8((size >> (i*8)) & 255)}
            data.replaceSubrange(156..<156+name.utf8.count,with:Data(name.utf8))
            data.replaceSubrange(168..<172,with:Data("GAME".utf8));data.replaceSubrange(220..<228,with:Data("GAMETSPP".utf8))
            for (index,value) in values.enumerated(){for i in 0..<4{data[236+index*4+i]=UInt8((value.bitPattern >> (i*8)) & 255)}}
            return data
        }
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let patch=root.appendingPathComponent("Selection.patch")
        let instrument=try TestFixtures.exs(in:patch)
        var strip=TestFixtures.mainStageStrip([instrument.lastPathComponent])
        strip.append(device("Gain",[-3,0,0,0,0,0,0]))
        strip.append(device("Chorus",[0.5,0.4,0.3]))
        let stripURL=patch.appendingPathComponent("First.cst")
        try strip.write(to:stripURL)
        let sourceHash=try AssetDigest.sha256(stripURL)
        let document:[String:Any]=["channels":[["Filename":"First.cst","Channel_name":"First","volume":1_509_949_440]]]
        try PropertyListSerialization.data(fromPropertyList:document,format:.binary,options:0).write(to:patch.appendingPathComponent("data.plist"))

        let store=PerformanceStore()
        store.importMainStagePatch(patch)
        guard let report=store.mainStageImportReport else{fatalError(store.libraryImportProgress ?? "No preflight report")}
        assert(report.channels.count==1 && report.channels[0].isConvertible)
        let draft=try store.mainStageProcessing(0)
        assert(draft.effects.map(\.kind)==[9,5],"Expected the source Gain and Chorus in source order")
        var selection=MainStageProcessing.Selection()
        selection.audio=[1]
        selection.midi=MIDIProgram(kind:.octaveUp)
        try store.setMainStageEffectSelection(selection,for:0)
        store.importMainStageSamplers(patch)
        for _ in 0..<1500 where store.libraryImportBusy {try await Task.sleep(nanoseconds:10_000_000)}
        assert(!store.libraryImportBusy)
        guard let entry=store.librarySounds.first(where:{$0.id.hasPrefix("mainstage-channel-")}),let layer=entry.layer else{fatalError(store.libraryImportProgress ?? "No converted channel")}
        assert(layer.effects.map(\.kind)==[5,0,0],"Only the selected Chorus may fill a visible slot")
        assert(layer.midiProgram?.kind == .octaveUp && layer.midiEffectEnabled)
        assert(layer.mainStageSource?.selectedAudio==[1] && layer.mainStageSource?.effects.count==2)
        assert(layer.mainStageSource?.omitted.contains{$0.contains("Gain")}==true)
        assert((entry.conversionNotes ?? []).contains{$0.contains("not selected")},"Omitted effects must be reported")
        assert(try AssetDigest.sha256(stripURL)==sourceHash,"Selection must not alter the retained source bytes")
        let restored=PerformanceStore()
        assert(restored.librarySounds.first(where:{$0.id==entry.id})?.layer?.midiProgram?.kind == .octaveUp)
        assert(restored.librarySounds.first(where:{$0.id==entry.id})?.layer?.effects.map(\.kind)==[5,0,0])
        print("PASS: store conversion applies only selected source slots, retains EQ/compressor mapping path, records omissions and persists selection without changing source bytes")
    }
}
