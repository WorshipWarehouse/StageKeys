import Foundation

/// End-to-end: a channel that only saved a third-party Audio Unit becomes a hosted
/// layer when that component is installed, and stays an explicit failure when it is not.
/// The installed list is injected, so no third-party plug-in is needed to run this.
@main struct MainStageAudioUnitImportTests {
    static func main()async throws {
        func fourCC(_ text:String)->[UInt8] {Array(text.utf8.reversed())}
        let payload=Data("<programs><program Val_0=\"0.1\"/><program Val_0=\"0.2\"/></programs>".utf8)
        var vendor=Data("VC2!".utf8)
        for i in 0..<4 {vendor.append(UInt8((payload.count >> (i*8)) & 255))}
        vendor.append(payload)
        let wrapper:[String:Any]=["name":"Accordion OB-Xa","type":0x61756d75,"subtype":0x4f627864,"manufacturer":0x44445350,"version":0,
                                  "data":Data(repeating:0,count:652),"element-name":["2":["0":"Output"]],"jucePluginState":vendor]
        let xml=try PropertyListSerialization.data(fromPropertyList:wrapper,format:.xml,options:0)
        var module=Data(repeating:0,count:180)
        module.replaceSubrange(0..<4,with:Data("UCuA".utf8))
        module.replaceSubrange(156..<161,with:Data("OB-Xd".utf8))
        module.replaceSubrange(168..<172,with:Data("PSDD".utf8))
        module.replaceSubrange(172..<176,with:Data(fourCC("aumu")))
        module.replaceSubrange(176..<180,with:Data(fourCC("Obxd")))
        module.append(xml)
        let size=module.count-8
        for i in 0..<4 {module[28+i]=UInt8((size >> (i*8)) & 255)}
        var strip=Data(repeating:0,count:36)
        strip.replaceSubrange(0..<4,with:Data("OCuA".utf8))
        strip.append(module);strip.append(Data(repeating:0,count:64))

        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        defer{try? FileManager.default.removeItem(at:root)}
        let patch=root.appendingPathComponent("AU Pad.patch",isDirectory:true)
        try FileManager.default.createDirectory(at:patch,withIntermediateDirectories:true)
        try strip.write(to:patch.appendingPathComponent("Pad.cst"))
        let document:[String:Any]=["patch":["engineNode":["name":"AU Fixture"]],"channels":[["Filename":"Pad.cst","Channel_name":"Pad","volume":535_750_245]]]
        try PropertyListSerialization.data(fromPropertyList:document,format:.binary,options:0).write(to:patch.appendingPathComponent("data.plist"))

        setenv("STAGEKEYS_DATA_DIR",root.appendingPathComponent("missing-data").path,1)
        let missing=PerformanceStore()
        missing.importMainStagePatch(patch)
        guard let missingReport=missing.mainStageImportReport,missingReport.channels.count==1,
              missingReport.channels[0].isConvertible,missingReport.channels[0].thirdPartyAudioUnits.first?.name=="OB-Xd" else{fatalError("An Audio Unit channel must be reported and selectable")}
        assert(missing.selectedMainStageChannels==[0],"A saved Audio Unit channel must be selectable for conversion")
        missing.importMainStageSamplers(patch,installedAudioUnits:[])
        for _ in 0..<1500 where missing.libraryImportBusy {try await Task.sleep(nanoseconds:20_000_000)}
        assert(!missing.libraryImportBusy && missing.librarySounds.isEmpty,"A missing Audio Unit must not commit a sound")
        let missingMessage=missing.libraryImportProgress ?? ""
        assert(missingMessage.contains("not installed") && missingMessage.contains("OB-Xd"),"A missing Audio Unit must be named: \(missingMessage)")

        let dataRoot=root.appendingPathComponent("data")
        setenv("STAGEKEYS_DATA_DIR",dataRoot.path,1)
        let store=PerformanceStore()
        store.importMainStagePatch(patch)
        assert(store.librarySounds.isEmpty,"Preflight must not commit a hosted sound")
        let installed=[ExternalAUIdentity(type:0x61756d75,subtype:0x4f627833,manufacturer:0x44445350,name:"OB-Xd",vendor:"discoDSP",version:"3.24.0")]
        store.importMainStageSamplers(patch,installedAudioUnits:installed)
        for _ in 0..<1500 where store.libraryImportBusy {try await Task.sleep(nanoseconds:20_000_000)}
        assert(!store.libraryImportBusy,"Audio Unit conversion did not finish")
        guard let entry=store.librarySounds.first(where:{$0.id.hasPrefix("mainstage-channel-")}),let layer=entry.layer else{fatalError(store.libraryImportProgress ?? "No hosted Audio Unit was added")}
        assert(entry.sound?.kind == .audioUnit && layer.external?.component?.subtype==0x4f627833,"The hosted layer must target the installed component")
        assert(layer.external?.component?.version=="3.24.0" && layer.pluginState != nil,"The saved state must travel with the layer")
        assert(entry.originalInstrument==nil && entry.sourceArchiveID==store.mainStageImportReport?.sourceArchiveID)
        let notes=(entry.conversionNotes ?? []).joined(separator:" ")
        assert(notes.contains("aumu/Obxd") && notes.contains("aumu/Obx3/DDSP") && notes.contains("3.24.0"),"A version change must name both components: \(notes)")
        assert(notes.contains("Accordion OB-Xa"),"The restored saved state must be described")
        let restored=(try? PropertyListSerialization.propertyList(from:layer.pluginState ?? Data(),options:[],format:nil)) as? [String:Any]
        assert((restored?["subtype"] as? NSNumber)?.uint32Value==0x4f627833 && restored?["jucePluginState"] as? Data==vendor,"The restorable state must target the installed component and keep the vendor payload")

        store.assembleConvertedMainStagePatch()
        guard let assembled=store.setlist.patches.last,assembled.layers.first?.external?.kind == .audioUnit else{fatalError(store.message ?? "No patch was assembled")}
        assert(assembled.layers.first?.pluginState==layer.pluginState,"The assembled patch must keep the plug-in state")
        assert(abs(layer.gain-pow(10,-18.0/20))<0.00001 && assembled.layers.first?.gain==layer.gain,"Native AU conversion and patch assembly must preserve the saved channel fader")
        let reloaded=PerformanceStore()
        assert(reloaded.librarySounds.first(where:{$0.id==entry.id})?.layer?.gain==layer.gain,"Imported source gain must survive a new store")
        let count=store.librarySounds.count
        store.importMainStagePatch(patch);store.importMainStageSamplers(patch,installedAudioUnits:installed)
        for _ in 0..<1500 where store.libraryImportBusy {try await Task.sleep(nanoseconds:20_000_000)}
        assert(store.librarySounds.count==count,"Reimporting must not duplicate the hosted Audio Unit: \(count) -> \(store.librarySounds.count) \(store.librarySounds.map{String($0.id.suffix(12))})")
        let repeated=try MainStagePatch.assembledChannels(store.mainStageImportReport!,entries:store.librarySounds)
        assert(repeated.layers.first?.gain==layer.gain,"Unchanged reimport must remain assemblable from its current archive")
        var changedDocument=document
        changedDocument["channels"]=[["Filename":"Pad.cst","Channel_name":"Pad","volume":1_509_949_440]]
        let changedBytes=try PropertyListSerialization.data(fromPropertyList:changedDocument,format:.binary,options:0)
        try changedBytes.write(to:patch.appendingPathComponent("data.plist"))
        store.importMainStagePatch(patch);store.importMainStageSamplers(patch,installedAudioUnits:installed)
        for _ in 0..<1500 where store.libraryImportBusy {try await Task.sleep(nanoseconds:20_000_000)}
        assert(!store.libraryImportBusy && store.librarySounds.count==count+1,"A metadata-only fader edit must import as a new version")
        let updated=try MainStagePatch.assembledChannels(store.mainStageImportReport!,entries:store.librarySounds)
        assert(updated.layers.first?.gain==1,"Metadata-only source fader edit was not applied")
        let updatedState=(try PropertyListSerialization.propertyList(from:updated.layers.first!.pluginState!,options:[],format:nil)) as! [String:Any]
        assert(NSDictionary(dictionary:updatedState).isEqual(NSDictionary(dictionary:restored!)),"Reimport must preserve all plugin-state values; plist serialization order need not be byte-identical")
        assert(store.librarySounds.first(where:{$0.id==entry.id})?.layer?.gain==layer.gain,"Old imported sounds must not be overwritten")
        let sourceAfter=try Data(contentsOf:patch.appendingPathComponent("data.plist"))
        let stripAfter=try Data(contentsOf:patch.appendingPathComponent("Pad.cst"))
        assert(sourceAfter==changedBytes && stripAfter==strip,"Conversion must preserve original source bytes")
        let importedBefore=store.librarySounds
        let retainedMetadata=dataRoot.appendingPathComponent("MainStage Sources/"+store.mainStageImportReport!.sourceArchiveID!+"/Source.patch/data.plist")
        let retainedBytes=try Data(contentsOf:retainedMetadata)
        try Data("changed after preflight".utf8).write(to:retainedMetadata)
        store.importMainStageSamplers(patch,installedAudioUnits:installed)
        for _ in 0..<1500 where store.libraryImportBusy {try await Task.sleep(nanoseconds:20_000_000)}
        assert(store.libraryImportProgress?.contains("changed or has no integrity record")==true,"Duplicate reuse must not bypass retained metadata verification")
        assert(store.librarySounds==importedBefore,"A failed duplicate integrity check must not alter the catalog")
        try retainedBytes.write(to:retainedMetadata)
        print("PASS: a saved third-party Audio Unit converts to a hosted layer with its state and version warning, assembles into a patch, is not duplicated on reimport, and is refused when the component is missing")
        print("PASS: unchanged reimport assembles, metadata-only edits retain new gain and original source/state, previous versions remain untouched")
    }
}
