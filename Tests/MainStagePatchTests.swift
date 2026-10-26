import Foundation
@main struct MainStagePatchTests {
    static func main()throws {
        for (name,family) in [("ES2","ES2"),("RetroSyn","Retro Synth"),("Sculpture","Sculpture"),("Alchemy","Alchemy")] {
            let channel=MainStagePatch.Channel(name:"Fixture",file:"x.cst",sha256:"hash",instruments:["unrelated.exs"],devices:[.init(name:name,offset:0,byteCount:1,format:"MELC")],hasMappings:false,hasMIDIState:false)
            assert(channel.unsupportedInstrumentFamily==family && channel.nativeInstrumentStatus.contains("Archive only"))
        }
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        defer{try? FileManager.default.removeItem(at:root)}
        // A saved third-party Audio Unit is a real device record: report it, do not drop it.
        func fourCC(_ text:String)->[UInt8] { Array(text.utf8.reversed()) }
        func module(_ name:String,_ signature:String,_ type:String?=nil,_ subtype:String?=nil)->Data {
            var record=Data(repeating:0,count:256);record.replaceSubrange(0..<4,with:Data("UCuA".utf8))
            let size=220;for i in 0..<4 {record[28+i]=UInt8((size >> (i*8)) & 255)}
            record.replaceSubrange(156..<156+name.utf8.count,with:Data(name.utf8))
            record.replaceSubrange(168..<172,with:Data(signature.utf8))
            if let type,let subtype {
                record.replaceSubrange(172..<176,with:Data(fourCC(type)))
                record.replaceSubrange(176..<180,with:Data(fourCC(subtype)))
            }
            return record
        }
        var auStrip=Data(repeating:0,count:36);auStrip.replaceSubrange(0..<4,with:Data("OCuA".utf8))
        auStrip.append(module("OB-Xd","PSDD","aumu","Obxd"))
        let auDevices=try MainStagePatch.devices(auStrip)
        assert(auDevices.count==1 && auDevices[0].name=="OB-Xd" && auDevices[0].format=="PSDD")
        assert(auDevices[0].audioUnitType=="aumu" && auDevices[0].audioUnitSubtype=="Obxd" && auDevices[0].audioUnitIdentity=="aumu/Obxd")
        let auChannel=MainStagePatch.Channel(name:"Pad",file:"Pad.cst",sha256:"hash",instruments:[],devices:auDevices,hasMappings:false,hasMIDIState:false)
        assert(auChannel.thirdPartyAudioUnits.map(\.name)==["OB-Xd"])
        assert(auChannel.nativeInstrumentStatus.contains("OB-Xd") && auChannel.nativeInstrumentStatus.contains("aumu/Obxd"))
        let auPatch=root.appendingPathComponent("AUPatch.patch",isDirectory:true)
        try FileManager.default.createDirectory(at:auPatch,withIntermediateDirectories:true)
        try auStrip.write(to:auPatch.appendingPathComponent("Pad.cst"))
        let auPlist:[String:Any]=["patch":["engineNode":["name":"AU Fixture"]],"channels":[["Filename":"Pad.cst","Channel_name":"Pad"]]]
        try PropertyListSerialization.data(fromPropertyList:auPlist,format:.binary,options:0).write(to:auPatch.appendingPathComponent("data.plist"))
        let auReport=try MainStagePatch.inspect(auPatch)
        assert(auReport.channels.first?.devices.map(\.name)==["OB-Xd"],"A saved Audio Unit must not be silently dropped")
        assert(auReport.blockers.contains{$0.contains("OB-Xd") && $0.contains("aumu/Obxd")},"The report must name the Audio Unit it cannot translate")
        var noiseStrip=Data(repeating:0,count:36);noiseStrip.replaceSubrange(0..<4,with:Data("OCuA".utf8))
        noiseStrip.append(module("HPQ/1RUX]hlq","v{U]"))
        // The PSDD document is a plug-in-state wrapper: identity, preset name and vendor bank.
        let payload=Data("<programs><program Val_0=\"0.1\"/><program Val_0=\"0.2\"/></programs>".utf8)
        var vendor=Data("VC2!".utf8)
        for i in 0..<4 {vendor.append(UInt8((payload.count >> (i*8)) & 255))}
        vendor.append(payload)
        let wrapper:[String:Any]=["name":"Accordion OB-Xa","type":0x61756d75,"subtype":0x4f627864,"manufacturer":0x44445350,"version":0,
                                    "data":Data(repeating:0,count:652),"element-name":["2":["0":"Output"]],"jucePluginState":vendor]
        let xml=try PropertyListSerialization.data(fromPropertyList:wrapper,format:.xml,options:0)
        var stateRecord=Data(repeating:0,count:180);stateRecord.append(xml)
        let parsed=MainStagePatch.pluginState(in:stateRecord)
        assert(parsed?.componentType=="aumu" && parsed?.componentSubtype=="Obxd" && parsed?.manufacturer=="DDSP")
        assert(parsed?.presetName=="Accordion OB-Xa" && parsed?.programCount==2 && parsed?.stateBytes==vendor.count)
        assert(parsed?.summary.contains("2-program bank")==true && parsed?.summary.contains("bytes")==true)
        assert(MainStagePatch.pluginState(in:Data(repeating:0,count:64))==nil,"A record without a wrapper has no plug-in state")
        var brokenWrapper=Data(repeating:0,count:180);brokenWrapper.append(Data("<?xml version=\"1.0\"?><plist><dict><key>".utf8))
        assert(MainStagePatch.pluginState(in:brokenWrapper)==nil,"A malformed wrapper must not produce state")
        var stateStrip=Data(repeating:0,count:36);stateStrip.replaceSubrange(0..<4,with:Data("OCuA".utf8))
        var stateModule=Data(repeating:0,count:180);stateModule.replaceSubrange(0..<4,with:Data("UCuA".utf8))
        stateModule.replaceSubrange(156..<161,with:Data("OB-Xd".utf8));stateModule.replaceSubrange(168..<172,with:Data("PSDD".utf8))
        stateModule.replaceSubrange(172..<176,with:Data(fourCC("aumu")));stateModule.replaceSubrange(176..<180,with:Data(fourCC("Obxd")))
        stateModule.append(xml)
        let stateSize=stateModule.count-8
        for i in 0..<4 {stateModule[28+i]=UInt8((stateSize >> (i*8)) & 255)}
        stateStrip.append(stateModule);stateStrip.append(Data(repeating:0,count:64))
        let stateDevices=try MainStagePatch.devices(stateStrip)
        assert(stateDevices.count==1 && stateDevices[0].pluginState?.programCount==2,"A device must carry its decoded plug-in state")
        try stateStrip.write(to:auPatch.appendingPathComponent("Pad.cst"))
        let stateReport=try MainStagePatch.inspect(auPatch)
        assert(stateReport.blockers.contains{$0.contains("Accordion OB-Xa") && $0.contains("2-program bank")},"The report must disclose retained plug-in state")
        // Saved class info must survive as the state a hosted AU would be given.
        let savedState=MainStagePatch.pluginStateData(in:stateRecord)
        assert(savedState != nil,"A valid wrapper must produce persistable state")
        let restoredState=(try? PropertyListSerialization.propertyList(from:savedState ?? Data(),options:[],format:nil)) as? [String:Any]
        assert(restoredState?["name"] as? String=="Accordion OB-Xa" && restoredState?["jucePluginState"] as? Data==vendor)
        let installed=[ExternalAUIdentity(type:0x61756d75,subtype:0x4f627833,manufacturer:0x44445350,name:"OB-Xd",vendor:"discoDSP",version:"3.24.0")]
        let stateDevice=stateDevices[0]
        let match=MainStageAudioUnit.match(stateDevice,state:savedState ?? Data(),installed:installed)
        assert(match?.exactSubtype==false && match?.savedVersion==0,"A version bump must be reported, not hidden")
        assert(match?.savedIdentity=="aumu/Obxd/DDSP" && match?.installedVersion=="3.24.0")
        let rewritten=(try? PropertyListSerialization.propertyList(from:match?.state ?? Data(),options:[],format:nil)) as? [String:Any]
        assert((rewritten?["subtype"] as? NSNumber)?.uint32Value==0x4f627833,"A version-changed match must target the installed component")
        assert(rewritten?["jucePluginState"] as? Data==vendor,"Rewriting identity must preserve the vendor state")
        let exact=[ExternalAUIdentity(type:0x61756d75,subtype:0x4f627864,manufacturer:0x44445350,name:"OB-Xd")]
        assert(MainStageAudioUnit.match(stateDevice,state:savedState ?? Data(),installed:exact)?.exactSubtype==true)
        let exactValues=(try? PropertyListSerialization.propertyList(from:MainStageAudioUnit.match(stateDevice,state:savedState ?? Data(),installed:exact)?.state ?? Data(),options:[],format:nil)) as? [String:Any]
        assert((exactValues?["subtype"] as? NSNumber)?.uint32Value==0x4f627864,"An exact match must keep the saved identity")
        let foreign=[ExternalAUIdentity(type:0x61756d75,subtype:0x4f627833,manufacturer:0x11111111,name:"OB-Xd")]
        assert(MainStageAudioUnit.match(stateDevice,state:savedState ?? Data(),installed:foreign)==nil,"A different manufacturer is not the same plug-in")
        assert(MainStageAudioUnit.match(stateDevice,state:savedState ?? Data(),installed:[])==nil)
        let extracted=MainStageAudioUnit.state(for:stateDevice,in:stateStrip)
        let extractedState=(try? PropertyListSerialization.propertyList(from:extracted ?? Data(),options:[],format:nil)) as? [String:Any]
        assert(extractedState?["jucePluginState"] as? Data==vendor,"State extraction must preserve the vendor state")
        assert(extractedState?["name"] as? String=="Accordion OB-Xa" && extractedState?["version"] as? Int==0)
        assert(MainStageAudioUnit.state(for:auDevices[0],in:auStrip)==nil,"A sampler device has no plug-in state")
        let noiseDevices=try MainStagePatch.devices(noiseStrip)
        assert(noiseDevices.isEmpty,"An unrecognized signature must stay unrecognized")
        let patch=root.appendingPathComponent("Fixture.patch",isDirectory:true)
        try FileManager.default.createDirectory(at:patch,withIntermediateDirectories:true)
        var bytes=Data(repeating:0,count:36);bytes.replaceSubrange(0..<4,with:Data("OCuA".utf8))
        var device=Data(repeating:0,count:256);device.replaceSubrange(0..<4,with:Data("UCuA".utf8))
        let size=220;for i in 0..<4 {device[28+i]=UInt8((size >> (i*8)) & 255)}
        device.replaceSubrange(156..<161,with:Data("EXS24".utf8));device.replaceSubrange(168..<172,with:Data("MELC".utf8))
        device.replaceSubrange(180..<192,with:Data("MELCPMAS1MAS".utf8));device.replaceSubrange(192..<203,with:Data("Fixture.exs".utf8))
        bytes.append(device);bytes.append(Data("MAPlugInParameterMapping".utf8))
        let strip=patch.appendingPathComponent("Piano.cst");try bytes.write(to:strip)
        let plist:[String:Any]=["patch":["engineNode":["name":"Authored Piano"]],"channels":[["Filename":"Piano.cst","Channel_name":"Piano","MIDITransform":["transforms":[["in":11]]]]]]
        try PropertyListSerialization.data(fromPropertyList:plist,format:.binary,options:0).write(to:patch.appendingPathComponent("data.plist"))
        let report=try MainStagePatch.inspect(patch)
        assert(report.name=="Authored Piano")
        assert(report.channels.count==1 && report.channels[0].devices.map(\.name)==["EXS24"])
        assert(report.channels[0].instruments==["Fixture.exs"] && report.channels[0].hasMappings && report.channels[0].hasMIDIState)
        assert(!report.complete,"Unknown processing cannot be declared a complete native conversion")
        let sample=patch.appendingPathComponent("Samples/Piano.caf")
        try FileManager.default.createDirectory(at:sample.deletingLastPathComponent(),withIntermediateDirectories:true)
        FileManager.default.createFile(atPath:sample.path,contents:nil)
        let handle=try FileHandle(forWritingTo:sample);try handle.truncate(atOffset:20_000_000);try handle.close()
        let sampleHash=try AssetDigest.sha256(sample)
        let destination=root.appendingPathComponent("archive",isDirectory:true)
        let retained=try MainStagePatch.retain(patch,to:destination)
        assert(retained==report)
        let copiedHash=try AssetDigest.sha256(destination.appendingPathComponent("Source.patch/Samples/Piano.caf"));assert(copiedHash==sampleHash,"Large bundled samples must be retained byte-for-byte without document-size rejection")
        let restored=try Data(contentsOf:destination.appendingPathComponent("Source.patch/Piano.cst"))
        assert(restored==bytes,"Source effects and mappings must be retained byte-for-byte")
        let archivedRoot=destination.appendingPathComponent("Source.patch"),archivedStrip=archivedRoot.appendingPathComponent("Piano.cst")
        let verified=try MainStagePatch.verifiedRead(archivedStrip,in:archivedRoot,sha256:report.channels[0].sha256);assert(verified==bytes)
        try Data("changed".utf8).write(to:archivedStrip)
        do{_ = try MainStagePatch.verifiedRead(archivedStrip,in:archivedRoot,sha256:report.channels[0].sha256);fatalError("Changed retained source accepted")}catch{}
        try bytes.write(to:archivedStrip)
        do{_ = try MainStagePatch.verifiedRead(archivedStrip,in:archivedRoot,sha256:nil);fatalError("Missing integrity record accepted")}catch{}

        do{_ = try MainStagePatch.retain(patch,to:destination);fatalError("Archive overwritten")}catch{}
        let cstArchive=root.appendingPathComponent("channel-archive"),cstReport=try MainStagePatch.retain(strip,to:cstArchive)
        assert(cstReport.name=="Piano" && cstReport.channels.count==1 && cstReport.blockers.contains{$0.contains("parent-patch")})
        let retainedCST=try Data(contentsOf:cstArchive.appendingPathComponent("Source.patch/Piano.cst"));assert(retainedCST==bytes,"CST import must preserve original device bytes")
        assert(cstReport.channels[0].instruments==["Fixture.exs"] && !cstReport.complete)
        do{_ = try MainStagePatch.devices(Data(repeating:0,count:64));fatalError("Invalid header accepted")}catch{}
        let unsafe:[String:Any]=["channels":[["Filename":"../outside.cst"]]]
        try PropertyListSerialization.data(fromPropertyList:unsafe,format:.binary,options:0).write(to:patch.appendingPathComponent("data.plist"))
        do{_ = try MainStagePatch.inspect(patch);fatalError("Traversal accepted")}catch{}
        print("PASS: MainStage source inspection, device/EXS detection, macro/MIDI retention, exact-byte archive, unsupported processing and unsafe path rejection")
    }
}
