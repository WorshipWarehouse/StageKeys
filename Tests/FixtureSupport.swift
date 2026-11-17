import Foundation
import AVFoundation

/// Only compiled by test runners, never by either app target. Explicit synthetic
/// files replace reliance on product factory/demo content; original assets are not used.
enum TestFixtures {
    private static var sounds:[String:ExternalSound]=[:]
    static func sound(_ index:Int=0)->ExternalSound {
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let key=root.path+"/\(index)"
        if let sound=sounds[key]{return sound}
        do {
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            let file=root.appendingPathComponent("Generated Fixture \(index).wav")
            let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
            let pcm=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:480000)!;pcm.frameLength=480000
            for frame in 0..<480000 {let phase=Float(frame)*2 * .pi*261.626/48000;pcm.floatChannelData![0][frame]=0.25*(sin(phase)+Float(index)*0.15*sin(phase*2))}
            do{let output=try AVAudioFile(forWriting:file,settings:format.settings);try output.write(from:pcm)}
            let controller=AudioController();let sound=try controller.externalRack!.importSound(file)
            sounds[key]=sound;return sound
        }catch{fatalError("Synthetic fixture failed: \(error)")}
    }
    static func layer(_ index:Int=0,gain:Float=0.6,name:String?=nil)->Layer {
        var layer=Layer(name:name ?? "Synthetic Fixture \(index)",instrument:-1,gain:gain)
        layer.external=sound(index);return layer
    }
    static func setlist()->Setlist {
        var setlist=Setlist();setlist.name="Synthetic Setlist"
        setlist.patches=(0..<3).map { index in
            let layers=[layer(0,gain:0.72),layer(1,gain:0.35),layer(2,gain:0)] + (0..<12).map{_ in Layer.empty()}
            return Patch(name:"Fixture Patch \(index)",layers:layers,snapshots:(0..<5).map{Snapshot(name:"Fixture Scene \($0)",gains:[0.65,0.2,0]+Array(repeating:0,count:12))})
        }
        setlist.assignments=[20:0,21:1,22:2];return setlist
    }
    static func padSound()->ExternalSound {
        do {
            let base=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
            _ = sound()
            let wave=base.appendingPathComponent("Generated Fixture 0.wav")
            let sampler=AVAudioUnitSampler();try sampler.loadAudioFiles(at:[wave])
            var state=sampler.auAudioUnit.fullStateForDocument!,instrument=state["Instrument"] as! [String:Any]
            var layers=instrument["Layers"] as! [[String:Any]]
            for i in layers.indices {
                var zones=layers[i]["Zones"] as! [[String:Any]]
                for j in zones.indices {zones[j]["min key"]=0;zones[j]["max key"]=127;zones[j]["root key"]=60;zones[j]["min velocity"]=1;zones[j]["max velocity"]=127;zones[j]["min vel"]=1;zones[j]["max vel"]=127;zones[j]["loop enabled"]=true;zones[j]["loop start"]=0;zones[j]["loop end"]=479999}
                layers[i]["Zones"]=zones
            }
            instrument["Layers"]=layers;state["Instrument"]=instrument
            let file=base.appendingPathComponent("Generated Loop.aupreset")
            try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:file)
            return try AudioController().externalRack!.importPreset(file,sampleRoot:base)
        }catch{fatalError("Synthetic loop fixture failed: \(error)")}
    }
}

extension TestFixtures {
    /// Minimal original legacy/modern EXS with one pitched sample, no proprietary content.
    static func exs(in folder:URL,name:String="Fixture.exs",modern:Bool=false)throws->URL {
        let source=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!).appendingPathComponent("Generated Fixture 0.wav")
        _ = sound()
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let wave=folder.appendingPathComponent("Fixture.wav")
        if !FileManager.default.fileExists(atPath:wave.path){try FileManager.default.copyItem(at:source,to:wave)}
        func put(_ body:inout [UInt8],_ offset:Int,_ value:UInt32){for i in 0..<4{body[offset+i]=UInt8(truncatingIfNeeded:value >> (i*8))}}
        func chunk(_ kind:UInt32,_ name:String,_ body:[UInt8])->Data {
            var header=[UInt8](repeating:0,count:84)
            put(&header,0,(kind << 24) | (modern ? 0x40000000:0) | 0x101);put(&header,4,UInt32(body.count))
            header.replaceSubrange(16..<20,with:Array("JBOS".utf8))
            header.replaceSubrange(20..<20+name.utf8.count,with:Array(name.utf8))
            return Data(header+body)
        }
        var sample=[UInt8](repeating:0,count:592)
        sample.replaceSubrange(80..<80+folder.path.utf8.count,with:Array(folder.path.utf8))
        sample.replaceSubrange(336..<347,with:Array("Fixture.wav".utf8))
        var zone=[UInt8](repeating:0,count:96);zone[1]=60;zone[7]=127;zone[10]=127
        put(&zone,16,479999);put(&zone,88,0xffffffff)
        let bytes=chunk(3,"Sample",sample)+chunk(1,"Zone",zone)
        let file=folder.appendingPathComponent(name);try bytes.write(to:file);return file
    }
    static func mainStageStrip(_ instruments:[String])->Data {
        var strip=Data(repeating:0,count:36);strip.replaceSubrange(0..<4,with:Data("OCuA".utf8))
        var device=Data(repeating:0,count:180)
        device.replaceSubrange(0..<4,with:Data("UCuA".utf8));device.replaceSubrange(156..<161,with:Data("EXS24".utf8));device.replaceSubrange(168..<172,with:Data("MELC".utf8))
        for name in instruments {device.append(Data("MELCPMAS1MAS".utf8));device.append(Data(name.utf8));device.append(0);device.append(Data(repeating:0,count:100))}
        let count=device.count-36
        for i in 0..<4{device[28+i]=UInt8(truncatingIfNeeded:count >> (i*8))}
        strip.append(device);return strip
    }
}

extension TestFixtures {
    /// Original two-layer stereo piano fixture: order-zero PCM residuals,
    /// independent fixed-width writer, no vendor bytes or copied test vectors.
    static func nordPiano() -> Data {
        let channels=2,block=1022*channels,count=2,frames=(block-2)/4-64
        let start=((0x732+count*118+192+block-1)/block)*block-192
        var body=[UInt8](repeating:0,count:start+count*block)
        func put(_ offset:Int,_ value:Int,_ bytes:Int=2) {for i in 0..<bytes {body[offset+i]=UInt8(truncatingIfNeeded:value >> ((bytes-1-i)*8))}}
        body.replaceSubrange(0..<4,with:Array("CNSP".utf8));put(4,0x464)
        body.replaceSubrange(0x1c..<0x1c+15,with:Array("Synthetic Piano".utf8))
        for key in 0..<128 {body[0x8c+key]=255}
        for key in 59...61 {body[0x8c+key]=60}
        body[0x18c+59]=UInt8(bitPattern:-2);body[0x18c+61]=2
        put(0x61c,0x464);put(0x61e,channels);put(0x620,count);put(0x622+60*2,count)
        for i in 0..<count {
            let r=0x732+i*118,at=start+i*block
            put(r,at,4);body[r+5]=UInt8(i*100);body[r+0x74]=UInt8(i*100)
            put(r+6,frames,4);put(r+10,1);put(r+0x1c,0,4);put(r+0x20,256,4)
            body[r+0x72]=20;put(at,16)
            for frame in 0..<(block-2)/4 {
                let sample=Int(sin(Double(frame)*2*Double.pi/128)*Double(i==0 ? 8000:2000))
                put(at+2+frame*4,sample);put(at+4+frame*4,-sample/2)
            }
        }
        var crc:UInt32=0xffffffff
        for byte in body {crc ^= UInt32(byte);for _ in 0..<8 {crc=(crc&1 != 0) ? (crc>>1)^0xedb88320:crc>>1}}
        crc ^= 0xffffffff
        var header=[UInt8](repeating:0,count:44)
        header.replaceSubrange(0..<4,with:Array("CBIN".utf8));header[4]=1
        header.replaceSubrange(8..<12,with:Array("npno".utf8));header[20]=88;header[21]=2
        for i in 0..<4 {header[24+i]=UInt8(truncatingIfNeeded:crc>>(i*8))}
        return Data(header+body)
    }
}
