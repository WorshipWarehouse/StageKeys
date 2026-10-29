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
