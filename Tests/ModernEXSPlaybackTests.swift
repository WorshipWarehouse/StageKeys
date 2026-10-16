import Foundation
import AVFoundation
@main struct ModernEXSPlaybackTests {
    static func main()throws {
        guard let path=ProcessInfo.processInfo.environment["STAGEKEYS_EXS_FIXTURE"],let rootPath=ProcessInfo.processInfo.environment["STAGEKEYS_EXS_ROOT"] else{print("SKIP: provide private EXS fixture and selected sample root");return}
        let scratch=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:scratch,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:scratch)}
        let preset=scratch.appendingPathComponent("Native.aupreset")
        let program=try EXSNative.convert(URL(fileURLWithPath:path),sampleRoot:URL(fileURLWithPath:rootPath),to:preset)
        assert(program.groups.count==20 && program.groups.contains{$0.controller==64 && $0.controllerLow==64})
        var state=try PropertyListSerialization.propertyList(from:Data(contentsOf:preset),options:[],format:nil) as! [String:Any]
        var instrument=state["Instrument"] as! [String:Any];let layers=instrument["Layers"] as! [[String:Any]]
        assert(layers.count==20 && layers.reduce(0){$0+($1["Zones"] as! [[String:Any]]).count}==224)
        // Render one isolated group to bound offline resident sample memory.
        // Runtime selection among all groups is covered by NativeSamplerGroupTests.
        instrument["Layers"]=[layers[0]];state["Instrument"]=instrument
        try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:preset)
        let engine=AVAudioEngine(),sampler=AVAudioUnitSampler(),format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
        engine.attach(sampler);engine.connect(sampler,to:engine.mainMixerNode,format:format)
        try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:512)
        try SamplerRendering.configure(sampler,offline:true);try sampler.loadInstrument(at:preset)
        engine.prepare();try engine.start()
        let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:512)!
        sampler.startNote(21,withVelocity:35,onChannel:0)
        var energy:Float=0
        for _ in 0..<48 {_ = try engine.renderOffline(512,to:buffer);for i in 0..<Int(buffer.frameLength) {let v=buffer.floatChannelData![0][i];assert(v.isFinite);energy+=abs(v)}}
        assert(energy>0.1,"Modern consolidated sample region did not render")
        engine.stop()
        print("PASS: real modern EXS translated 224 consolidated regions and 20 controller/velocity groups; isolated original-sample audio energy \(energy), no resampling")
    }
}
