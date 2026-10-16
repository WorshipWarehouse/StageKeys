import Foundation
import AVFoundation
@main struct NativeSamplerGroupTests {
    static func main()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:root)}
        let wave=root.appendingPathComponent("tone.wav"),format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
        let pcm=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:48000)!;pcm.frameLength=48000
        for i in 0..<48000{pcm.floatChannelData![0][i]=0.2*sin(Float(i)*2 * .pi*220/48000)}
        do{let file=try AVAudioFile(forWriting:wave,settings:format.settings);try file.write(from:pcm)}
        let sampler=AVAudioUnitSampler();try sampler.loadAudioFiles(at:[wave])
        var state=sampler.auAudioUnit.fullStateForDocument!;var instrument=state["Instrument"] as! [String:Any]
        let template=(instrument["Layers"] as! [[String:Any]])[0]
        var layers:[[String:Any]]=[]
        for i in 0..<2 {
            var layer=template;layer["ID"]=i
            var zones=layer["Zones"] as! [[String:Any]]
            for z in zones.indices{zones[z]["min key"]=0;zones[z]["max key"]=127;zones[z]["root key"]=i==0 ? 60:48}
            layer["Zones"]=zones
            if var connections=layer["Connections"] as? [[String:Any]] {for j in connections.indices{for key in ["source","destination","control"]{if let value=connections[j][key] as? Int,value>=0x10000000{connections[j][key]=value+i*256}}};layer["Connections"]=connections}
            layers.append(layer)
        }
        instrument["Layers"]=layers;state["Instrument"]=instrument
        let preset=root.appendingPathComponent("groups.aupreset")
        let program=NativeSamplerProgram(groups:[.init(name:"Dry",layer:0,low:0,high:127,velocityLow:1,velocityHigh:127,controller:64,controllerLow:0,controllerHigh:63),.init(name:"Pedal",layer:1,low:0,high:127,velocityLow:1,velocityHigh:127,controller:64,controllerLow:64,controllerHigh:127)],notes:[],compactGroups:true)
        state["StageKeys.NativeSampler"]=try JSONEncoder().encode(program)
        try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:preset)
        let audio=AudioController();try audio.prepareOffline()
        let sound=try audio.externalRack!.importPreset(preset,sampleRoot:root)
        assert(sound.nativeSampler==program,"Reimport must preserve native group/MIDI metadata for portable playback")
        var layer=Layer(name:"Groups",instrument:-1,gain:0.5);layer.external=sound
        var error:String?;audio.onError={error=$0};audio.configure(0,layer);audio.gain(0,0.5)
        assert(error==nil,error ?? "")
        func crossings(_ controller:UInt8)throws->Int {
            audio.panic();audio.externalRack!.control(channel:0,controller:64,value:controller)
            audio.noteOn(key:60,pitch:60,instrument:-1,layer:0,velocity:0.8)
            var previous:Float=0,count=0,energy:Float=0
            for block in 0..<24 {
                let buffer=try audio.offlineBlock()
                for i in 0..<Int(buffer.frameLength) {let v=buffer.floatChannelData![0][i];if block>4 {if previous<=0 && v>0{count+=1};energy+=abs(v)};previous=v}
            }
            assert(energy>0.1);return count
        }
        let dry=try crossings(0),pedal=try crossings(127)
        assert(Double(pedal)/Double(dry)>1.8 && Double(pedal)/Double(dry)<2.2,"CC64 must select exactly one native group, not stack both")
        assert(SamplerControllerGate(controller:64,low:0,high:63).accepts([:]))
        assert(!SamplerControllerGate(controller:64,low:64,high:127).accepts([:]))
        var gain=AudioEffect();gain.kind=9;gain.parameters=[-12]
        var processing=ImportedRack(effects:[gain])
        processing.macros=[ImportedMacro(index:0,name:"Gain",value:0,bindings:[ImportedMacroBinding(effect:0,parameter:0,minimum:-12,maximum:0)],midiCC:71,midiChannel:2)]
        layer.importedRack=processing;audio.configure(0,layer)
        let dryAfter=try crossings(0),pedalAfter=try crossings(127)
        assert(Double(pedalAfter)/Double(dryAfter)>1.8,"FX-only racks and snapshots must retain instrument group selection")
        func energy()throws->Float {
            audio.panic();audio.externalRack!.control(channel:0,controller:64,value:0)
            audio.noteOn(key:60,pitch:60,instrument:-1,layer:0,velocity:0.8)
            var sum:Float=0
            for block in 0..<24 {let buffer=try audio.offlineBlock();if block>4 {for i in 0..<Int(buffer.frameLength){sum+=abs(buffer.floatChannelData![0][i])}}}
            return sum
        }
        let quiet=try energy();assert(processing.applyMIDI(controller:71,value:127,channel:2))
        layer.importedRack=processing;audio.configure(0,layer);let loud=try energy()
        assert(loud/quiet>3.5 && loud/quiet<4.5,"Translated gain macro must change actual native audio")
        print("PASS: active native gain macro audio ratio \(loud/quiet)")
        print("PASS: active native sampler CC64 group selection, exclusive audible pitch and panic reset; dry \(dry), pedal \(pedal)")
    }
}
