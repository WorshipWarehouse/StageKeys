import Foundation
@main struct MainStagePatchTests {
    static func main()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        defer{try? FileManager.default.removeItem(at:root)}
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
