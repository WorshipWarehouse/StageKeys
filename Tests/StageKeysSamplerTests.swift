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
        assert(map.zones[0].low==48 && map.zones[0].high==72 && map.zones[0].root==60 && map.zones[0].velocityLow==32 && map.zones[0].velocityHigh==63 && map.zones[0].looped)
        let original=try StageKeysSampler.retainOriginal(source,library:root)
        let retained=try Data(contentsOf:root.appendingPathComponent(original.file))
        assert(retained==bytes && original.sha256==MainStagePatch.digest(bytes))
        let repeated=try StageKeysSampler.retainOriginal(source,library:root);assert(repeated==original)
        print("PASS: StageKeys Sampler key/velocity/root/loop map and exact-byte original instrument retention")
    }
}
