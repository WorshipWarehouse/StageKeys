import Foundation

@main struct MainStagePreflightTests {
    static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let patch=root.appendingPathComponent("Original.patch")
        try FileManager.default.createDirectory(at:patch,withIntermediateDirectories:true)
        var bytes=Data(repeating:0,count:36);bytes.replaceSubrange(0..<4,with:Data("OCuA".utf8))
        var device=Data(repeating:0,count:256);device.replaceSubrange(0..<4,with:Data("UCuA".utf8))
        for i in 0..<4 {device[28+i]=UInt8((220 >> (i*8)) & 255)}
        device.replaceSubrange(156..<161,with:Data("EXS24".utf8));device.replaceSubrange(168..<172,with:Data("MELC".utf8))
        device.replaceSubrange(180..<192,with:Data("MELCPMAS1MAS".utf8));device.replaceSubrange(192..<203,with:Data("Fixture.exs".utf8))
        bytes.append(device)
        try bytes.write(to:patch.appendingPathComponent("First.cst"))
        try bytes.write(to:patch.appendingPathComponent("Second.cst"))
        let document:[String:Any]=["channels":[["Filename":"First.cst","Channel_name":"First"],["Filename":"Second.cst","Channel_name":"Second"]]]
        try PropertyListSerialization.data(fromPropertyList:document,format:.binary,options:0).write(to:patch.appendingPathComponent("data.plist"))
        // A malformed included instrument must never be opened by preflight as a playable sound.
        try Data("original fixture, not a playable EXS".utf8).write(to:patch.appendingPathComponent("Fixture.exs"))
        let store=PerformanceStore(),originalCount=store.librarySounds.count
        store.importMainStagePatch(patch)
        assert(!store.libraryImportBusy && store.librarySounds.count==originalCount)
        assert(store.mainStageImportReport?.channels.count==2 && store.selectedMainStageChannels==[0,1])
        store.selectMainStageChannel(0,false);assert(store.selectedMainStageChannels==[1])
        store.selectMainStageChannel(1,false);assert(store.selectedMainStageChannels.isEmpty)
        store.selectMainStageChannel(100,true);assert(store.selectedMainStageChannels.isEmpty)
        let samples=root.appendingPathComponent("Authorized Samples")
        try FileManager.default.createDirectory(at:samples,withIntermediateDirectories:true)
        store.rememberMainStageSampleFolder(samples)
        assert(store.rememberedMainStageLocations().map(\.instruments.standardizedFileURL).contains(samples.standardizedFileURL))
        let restored=PerformanceStore()
        assert(restored.rememberedMainStageLocations().map(\.instruments.standardizedFileURL).contains(samples.standardizedFileURL))
        let source=try Data(contentsOf:patch.appendingPathComponent("First.cst"));assert(source==bytes)
        print("PASS: preflight retains source without committing sounds; channel selection and authorized sample-folder bookmarks persist")
    }
}
