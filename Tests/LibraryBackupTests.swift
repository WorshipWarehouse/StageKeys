import Foundation
import AVFoundation
@main struct LibraryBackupTests {
    static func main()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        defer{try? FileManager.default.removeItem(at:root)}
        try FileManager.default.createDirectory(at:root.appendingPathComponent("Imported Sounds"),withIntermediateDirectories:true)
        let wave=root.appendingPathComponent("Imported Sounds/tone.wav"),format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
        let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:12000)!;buffer.frameLength=12000
        for i in 0..<12000{buffer.floatChannelData![0][i]=0.2*sin(Float(i)*2 * .pi*220/48000)}
        do{let file=try AVAudioFile(forWriting:wave,settings:format.settings);try file.write(from:buffer)}
        let sampler=AVAudioUnitSampler();try sampler.loadAudioFiles(at:[wave])
        var state=sampler.auAudioUnit.fullStateForDocument!;let refs=state["file-references"] as! [String:String]
        state["file-references"]=refs.mapValues{_ in LibraryBackup.token+"/Imported Sounds/tone.wav"}
        let preset=root.appendingPathComponent("Imported Sounds/tone.aupreset")
        try PropertyListSerialization.data(fromPropertyList:state,format:.binary,options:0).write(to:preset)
        let sound=ExternalSound(kind:.samplerPreset,name:"Pack Piano",fileName:preset.lastPathComponent)
        var layer=Layer(name:"Pack Piano",instrument:-1,gain:0.432);layer.external=sound;layer.pan=0.2;layer.blockSustain=true
        var gain=AudioEffect();gain.kind=9;gain.parameters=[-9];layer.importedRack=ImportedRack(effects:[gain])
        let entry=LibrarySound(id:"pack-piano",name:"Pack Piano",collection:"My Pack",sound:sound,layer:layer,tags:.init(category:"Acoustic Piano & Keys",type:"Acoustic Piano",noteRanges:["Full Range"]))
        let catalog=root.appendingPathComponent("sound-library.json");try JSONEncoder().encode([entry]).write(to:catalog)
        var files:[String:String]=[:]
        for file in [wave,preset,catalog]{files[String(file.path.dropFirst(root.path.count+1))]=try AssetDigest.sha256(file)}
        let manifest:[String:Any]=["format":"stagekeys-private-library","version":1,"files":files]
        try JSONSerialization.data(withJSONObject:manifest).write(to:root.appendingPathComponent("manifest.json"))
        let pack=try LibraryBackup.read(root);assert(pack.sounds.count==1)
        let store=PerformanceStore(),encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        let before=try encoder.encode(store.setlist)
        store.importLibraryBackup(root)
        let deadline=Date().addingTimeInterval(30)
        while store.libraryImportBusy && Date()<deadline {_ = RunLoop.current.run(mode:.default,before:Date().addingTimeInterval(0.01))}
        assert(!store.libraryImportBusy && store.librarySounds.count==1,store.libraryImportProgress ?? "Import timed out")
        let installed=store.librarySounds[0];assert(installed.layer?.gain==layer.gain && installed.layer?.pan==layer.pan && installed.layer?.importedRack==layer.importedRack && installed.tags==entry.tags)
        let after=try encoder.encode(store.setlist);assert(before==after,"Library installation must not change the active setlist")
        store.tonicVelocitySelector=true
        store.setTonicInstrument(installed.sound!) // one-shot tone is not a looped pad
        assert(store.tonicSound==nil && store.tonicVelocitySelector,"Unsupported pad selection must preserve the existing pad mode")
        assert(store.message?.contains("unsupported key/velocity selector")==true)
        try Data("changed".utf8).write(to:wave)
        do{_ = try LibraryBackup.asset("Imported Sounds/tone.wav",in:pack.root,manifest:pack.manifest);assertionFailure("Changed asset accepted")}catch{}
        do{_ = try LibraryBackup.asset("../outside",in:pack.root,manifest:pack.manifest);assertionFailure("Traversal accepted")}catch{}
        print("PASS: optional pack install, portable sample relinking, original rack/tags/levels, active setlist preservation and hash/path rejection")
    }
}
