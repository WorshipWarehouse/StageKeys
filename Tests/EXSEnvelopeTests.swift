import Foundation
import AVFoundation
@main struct EXSEnvelopeTests {
    static func main()throws {
        let values:[(UInt8,Int16)]=[(0x52,0),(0x53,19),(0x54,94),(0x51,0),(0x55,71)]
        var parameters=Data([UInt8(values.count),0,0,0]);parameters.append(contentsOf:values.map(\.0))
        for (_,value) in values{let bits=UInt16(bitPattern:value);parameters.append(UInt8(bits & 255));parameters.append(UInt8(bits >> 8))}
        let envelope=try EXSNative.envelope([.init(kind:4,modern:false,index:0,name:"Parameters",body:[UInt8](parameters))])!
        assert(abs(envelope.decay-3)<0.01 && abs(envelope.release-0.977)<0.01 && envelope.sustain==0)
        assert(abs(envelope.lowVelocityAttack-0.005)<0.0001)
        do{_ = try EXSNative.parameters([255,255,255,127]);assertionFailure("Malformed count accepted")}catch{}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let wave=root.appendingPathComponent("loop.wav"),format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
        let pcm=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:48000)!;pcm.frameLength=48000
        for i in 0..<48000{pcm.floatChannelData![0][i]=0.2*sin(Float(i)*2 * .pi*220/48000)}
        do{let file=try AVAudioFile(forWriting:wave,settings:format.settings);try file.write(from:pcm)}
        let sampler=AVAudioUnitSampler();try sampler.loadAudioFiles(at:[wave])
        var state=sampler.auAudioUnit.fullStateForDocument!,instrument=state["Instrument"] as! [String:Any]
        var layer=(instrument["Layers"] as! [[String:Any]])[0],zones=layer["Zones"] as! [[String:Any]]
        zones[0]["root key"]=60;zones[0]["loop enabled"]=true;zones[0]["loop start"]=0;zones[0]["loop end"]=47999;layer["Zones"]=zones
        let group=[UInt8](repeating:0,count:120)
        EXSNative.applyEnvelope(envelope,group:group,to:&layer)
        instrument["Layers"]=[layer];state["Instrument"]=instrument
        let preset=root.appendingPathComponent("envelope.aupreset");try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:preset)
        let engine=AVAudioEngine();engine.attach(sampler);engine.connect(sampler,to:engine.mainMixerNode,format:format)
        try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:480)
        try SamplerRendering.configure(sampler,offline:true);try sampler.loadInstrument(at:preset);engine.prepare();try engine.start()
        defer{engine.stop()}
        let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:480)!
        func render(_ blocks:Int)throws->Double {
            var energy=0.0
            for _ in 0..<blocks {_ = try engine.renderOffline(480,to:buffer);for i in 0..<Int(buffer.frameLength){let v=buffer.floatChannelData![0][i];assert(v.isFinite);energy+=Double(v*v)}}
            return energy/Double(blocks*480)
        }
        sampler.startNote(60,withVelocity:100,onChannel:0)
        let attack=try render(20);let early=try render(50);_ = try render(170);let late=try render(50);_ = try render(50);let ended=try render(50)
        assert(attack>0.00001 && early>late*2,"Source decay must reduce sustained audio")
        assert(ended<early*0.001,"Source zero sustain must reach silence after the source decay")
        sampler.stopNote(60,onChannel:0);_ = try render(120)
        sampler.startNote(60,withVelocity:100,onChannel:0);_ = try render(20);sampler.stopNote(60,onChannel:0)
        let tail=try render(20);_ = try render(100);let silence=try render(30)
        assert(tail>0.000001 && silence<tail*0.001,"Source release must ring and then finish")
        print("PASS: EXS parameter bounds/time curve and actual native decay/release audio; early \(early), late \(late), ended \(ended), release \(tail), silence \(silence)")
    }
}
