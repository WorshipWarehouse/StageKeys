import Foundation
import AVFoundation
@main struct ModernEXSImportTests {
    static func main()throws {
        guard let path=ProcessInfo.processInfo.environment["STAGEKEYS_EXS_FIXTURE"],let root=ProcessInfo.processInfo.environment["STAGEKEYS_EXS_ROOT"] else{print("SKIP: provide private EXS fixture and selected sample root");return}
        let scratch=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        defer{try? FileManager.default.removeItem(at:scratch)}
        let source=URL(fileURLWithPath:path),original=try AbletonArchive.sha256(source)
        let rack=try ExternalInstrumentRack(engine:AVAudioEngine(),libraryURL:scratch.appendingPathComponent("samples"))
        let sound=try rack.importEXS(source,sampleRoot:URL(fileURLWithPath:root))
        assert(sound.nativeSampler?.groups.count==20 && sound.nativeSampler?.rack.validate()==true && sound.nativeSampler?.rack.branches?.count==2)
        let map=try StageKeysSampler.map(sound,library:rack.libraryURL)
        assert(map.zones.count==224 && map.layerCount==20 && map.sampleCount==1)
        let state=try PropertyListSerialization.propertyList(from:Data(contentsOf:rack.libraryURL.appendingPathComponent(sound.fileName!)),options:[],format:nil) as! [String:Any]
        let refs=state["file-references"] as! [String:String]
        let sourceAudio=URL(fileURLWithPath:root).appendingPathComponent("EXS Factory Samples/01 Acoustic Pianos/Steinway Piano_consolidated.caf")
        let copiedAudio=URL(fileURLWithPath:refs.values.first!)
        let sourceHash=try AbletonArchive.sha256(sourceAudio),copyHash=try AbletonArchive.sha256(copiedAudio)
        assert(sourceHash==copyHash,"Import must preserve the complete original CAF byte-for-byte")
        let after=try AbletonArchive.sha256(source);assert(after==original)
        let retained=try StageKeysSampler.retainOriginal(source,library:scratch)
        assert(retained.sha256==original)
        print("PASS: real EXS import API fallback, 224 zones/20 MIDI-selected groups, identical original CAF SHA-256 and unchanged EXS source")
    }
}
