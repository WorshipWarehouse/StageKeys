import Foundation
import AVFoundation
import zlib
@main struct AbletonImportTests {
    static func peak(_ preset:URL,note:UInt8,velocity:UInt8)throws->Float {
        let e=AVAudioEngine(),s=AVAudioUnitSampler();e.attach(s);e.connect(s,to:e.mainMixerNode,format:nil)
        let f=AVAudioFormat(standardFormatWithSampleRate:44100,channels:2)!
        try e.enableManualRenderingMode(.offline,format:f,maximumFrameCount:512);try s.loadInstrument(at:preset);try e.start();defer{e.stop()}
        let b=AVAudioPCMBuffer(pcmFormat:f,frameCapacity:512)!;s.startNote(note,withVelocity:velocity,onChannel:0);var peak:Float=0
        for _ in 0..<120{_ = try e.renderOffline(512,to:b);for c in 0..<2{for i in 0..<Int(b.frameLength){let v=b.floatChannelData![c][i];assert(v.isFinite);peak=max(peak,abs(v))}}};return peak
    }
    static func main()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let f=AVAudioFormat(standardFormatWithSampleRate:44100,channels:2)!,b=AVAudioPCMBuffer(pcmFormat:f,frameCapacity:44100)!
        b.frameLength=44100;for c in 0..<2{for i in 0..<44100{b.floatChannelData![c][i]=sin(Float(i)*2*Float.pi*220/44100)*0.2}}
        let sample=root.appendingPathComponent("Tone.wav");try AVAudioFile(forWriting:sample,settings:f.settings).write(from:b)
        let original=try AbletonArchive.sha256(sample)
        func branch(_ key:Int,_ low:Int,_ high:Int)->String {
            """
            <InstrumentBranchPreset><Name Value="Layer"/><ZoneSettings><KeyRange><Min Value="\(key)"/><Max Value="\(key)"/></KeyRange><VelocityRange><Min Value="\(low)"/><Max Value="\(high)"/></VelocityRange></ZoneSettings><DevicePresets><AbletonDevicePreset><Device><OriginalSimpler><Player><MultiSampleMap><SampleParts><MultiSamplePart><IsActive Value="true"/><RootKey Value="\(key)"/><SampleStart Value="0"/><SampleEnd Value="44099"/><SustainLoop><Mode Value="1"/><Start Value="100"/><End Value="18000"/><Crossfade Value="0"/></SustainLoop><SampleRef><FileRef><Name Value="Tone.wav"/></FileRef></SampleRef></MultiSamplePart></SampleParts></MultiSampleMap></Player></OriginalSimpler></Device></AbletonDevicePreset></DevicePresets></InstrumentBranchPreset>
            """
        }
        let xml="<Ableton><GroupDevicePreset><Device><InstrumentGroupDevice/></Device><BranchPresets>"+branch(48,1,63)+branch(72,64,127)+"</BranchPresets></GroupDevicePreset></Ableton>"
        let adg=root.appendingPathComponent("Fixture.adg"),out=root.appendingPathComponent("Fixture.aupreset")
        try Data(xml.utf8).write(to:adg)
        let conversion=try AbletonImport.convert(adg,sampleRoot:root,to:out)
        assert(conversion.layers==2 && conversion.zones==2)
        let check1 = try peak(out,note:48,velocity:32)>0.001;assert(check1)
        let check2 = try peak(out,note:72,velocity:100)>0.001;assert(check2)
        let check3 = try peak(out,note:48,velocity:100)<0.000001;assert(check3)
        let check4 = try peak(out,note:60,velocity:100)<0.000001;assert(check4)
        let check5 = try AbletonArchive.sha256(sample)==original;assert(check5)
        let check6 = try AbletonImport.validatePlayback(out)==2;assert(check6)
        // Native preset retains the explicit source loop and branch key/velocity limits.
        let state=try PropertyListSerialization.propertyList(from:Data(contentsOf:out),options:[],format:nil) as! [String:Any]
        let layers=(state["Instrument"] as! [String:Any])["Layers"] as! [[String:Any]]
        let zone=(layers[1]["Zones"] as! [[String:Any]])[0]
        assert(zone["min key"] as? Int==72 && zone["min vel"] as? Int==64 && zone["loop start"] as? Int==100)
        try Data(xml.replacingOccurrences(of:"Tone.wav",with:"../Tone.wav").utf8).write(to:adg)
        do{_ = try AbletonImport.convert(adg,sampleRoot:root,to:out);fatalError("Traversal accepted")}catch{}
        try Data("<!DOCTYPE Ableton [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><Ableton/>".utf8).write(to:adg)
        do{_ = try AbletonImport.readXML(adg);fatalError("Entities accepted")}catch{}
        // A bounded synthetic pl-a record tests native extraction without third-party assets.
        let audio=try Data(contentsOf:sample)
        func archive(_ name:String,offset:UInt64=16)->Data {
            var raw=Data("pl-a".utf8);let index=UInt64(16+audio.count)
            func append(_ value:UInt64,_ bytes:Int,to data:inout Data){for i in 0..<bytes{data.append(UInt8(truncatingIfNeeded:value >> (8*i)))}}
            append(index,8,to:&raw);raw.append(contentsOf:[0,0,0,1]);raw.append(audio)
            raw.append(contentsOf:[0,11]);raw.append(Data("PackageItem".utf8));append(0,4,to:&raw);append(UInt64(name.utf16.count),4,to:&raw);raw.append(name.data(using:.utf16LittleEndian)!)
            raw.append(Data(repeating:0,count:12));append(offset,8,to:&raw);append(UInt64(audio.count),8,to:&raw);return raw
        }
        let raw=archive("Tone.wav");let records=try AbletonArchive.members(raw);assert(records.count==1)
        for bad in [archive("../Tone.wav"),archive("Tone.wav",offset:UInt64.max)]{do{_ = try AbletonArchive.members(bad);fatalError("Unsafe member accepted")}catch{}}
        let alp=root.appendingPathComponent("Fixture.alp");let gz=gzopen(alp.path,"wb")!
        raw.withUnsafeBytes{p in assert(gzwrite(gz,p.baseAddress,UInt32(raw.count))==Int32(raw.count))};gzclose(gz)
        let extracted=try AbletonArchive.extract(alp);defer{try? FileManager.default.removeItem(at:extracted)}
        let check7 = try AbletonArchive.sha256(extracted.appendingPathComponent("Samples/Tone.wav"))==original;assert(check7)
        print("PASS: Ableton native multilayer/velocity playback, loops, original sample hashes, XML rejection and bounded ALP extraction")
    }
}
