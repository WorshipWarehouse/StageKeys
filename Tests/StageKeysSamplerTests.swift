import Foundation
@main struct StageKeysSamplerTests {
    static func main()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        defer{try? FileManager.default.removeItem(at:root)}
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let source=root.appendingPathComponent("Instrument.aupreset")
        let zone:[String:Any]=["name":"Piano C4 soft","min key":48,"max key":72,"root key":60,"min vel":1,"max vel":63,"loop enabled":true,"waveform":123]
        let state:[String:Any]=["Instrument":["Layers":[["min vel":32,"max vel":100,"Zones":[zone]]] ],"file-references":["Sample:123":"/private/original/Piano.wav"]]
        let bytes=try PropertyListSerialization.data(fromPropertyList:state,format:.binary,options:0)
        try bytes.write(to:source)
        let sound=ExternalSound(kind:.samplerPreset,name:"Piano",fileName:source.lastPathComponent)
        let map=try StageKeysSampler.map(sound,library:root)
        assert(map.sampleCount==1 && map.layerCount==1 && map.zones.count==1)
        assert(StageKeysSampler.tonicVelocitySelector(map)==nil,"Partial, non-looped maps must not be eligible for Tonic Pad selection")
        let loopedPad=StageKeysSampler.Map(sampleCount:1,zones:[StageKeysSampler.Zone(id:0,low:0,high:127,velocityLow:1,velocityHigh:127,root:60,sample:"Pad",looped:true)],layerCount:1,amplitudeEnvelope:nil)
        assert(StageKeysSampler.tonicVelocitySelector(loopedPad)==false,"A looped full-range zone supports normal Tonic Pad velocity")
        let oneShotZone=StageKeysSampler.Zone(id:0,low:0,high:127,velocityLow:1,velocityHigh:127,root:60,sample:"One shot",looped:false)
        let oneShot=StageKeysSampler.Map(sampleCount:1,zones:[oneShotZone],layerCount:1,amplitudeEnvelope:nil)
        assert(StageKeysSampler.tonicVelocitySelector(oneShot)==nil,"A full-range one-shot is not a sustainable pad")
        let mixedZones=[loopedPad.zones[0],StageKeysSampler.Zone(id:1,low:42,high:47,velocityLow:1,velocityHigh:127,root:42,sample:"Bright",looped:false)]
        assert(StageKeysSampler.tonicVelocitySelector(.init(sampleCount:2,zones:mixedZones,layerCount:1,amplitudeEnvelope:nil))==nil,"A one-shot layer selected at normal velocity must not be accepted")
        let splitZones=[StageKeysSampler.Zone(id:0,low:36,high:41,velocityLow:1,velocityHigh:127,root:36,sample:"Low",looped:true),StageKeysSampler.Zone(id:1,low:42,high:47,velocityLow:1,velocityHigh:127,root:42,sample:"High",looped:true)]
        assert(StageKeysSampler.tonicVelocitySelector(.init(sampleCount:2,zones:splitZones,layerCount:1,amplitudeEnvelope:nil))==false,"Looped split zones can cover the pad range")
        let selectorZones=(0..<12).map{index in StageKeysSampler.Zone(id:index,low:36,high:47,velocityLow:index+1,velocityHigh:index+1,root:36+index,sample:"Tone \(index)",looped:false)}
        let selector=StageKeysSampler.Map(sampleCount:12,zones:selectorZones,layerCount:1,amplitudeEnvelope:nil)
        assert(StageKeysSampler.tonicVelocitySelector(selector)==true,"The exact twelve-velocity selector remains eligible")
        assert(map.zones[0].low==48 && map.zones[0].high==72 && map.zones[0].root==60 && map.zones[0].velocityLow==32 && map.zones[0].velocityHigh==63 && map.zones[0].looped)
        let original=try StageKeysSampler.retainOriginal(source,library:root)
        let retained=try Data(contentsOf:root.appendingPathComponent(original.file))
        assert(retained==bytes && original.sha256==MainStagePatch.digest(bytes))
        let repeated=try StageKeysSampler.retainOriginal(source,library:root);assert(repeated==original)
        print("PASS: StageKeys Sampler key/velocity/root/loop map and exact-byte original instrument retention")
    }
}
