import Foundation
import CryptoKit

/// The StageKeys instrument UI and asset model; playback uses the system sampler,
/// never a MainStage process or its private Sampler plug-in.
enum StageKeysSampler {
    struct Zone:Identifiable,Equatable {
        var id:Int
        var low:Int
        var high:Int
        var velocityLow:Int
        var velocityHigh:Int
        var root:Int
        var sample:String
        var looped:Bool
    }
    struct Map:Equatable {
        var sampleCount:Int
        var zones:[Zone]
        var layerCount:Int
    }
    static func map(_ sound:ExternalSound,library:URL)throws->Map {
        guard sound.kind == .samplerPreset,let name=sound.fileName,name==URL(fileURLWithPath:name).lastPathComponent else{throw ExternalInstrumentError.unsupportedFormat}
        let file=library.appendingPathComponent(name)
        let bytes=try Data(contentsOf:file)
        guard bytes.count<=16_000_000,
              let state=try PropertyListSerialization.propertyList(from:bytes,options:[],format:nil) as? [String:Any],
              let instrument=state["Instrument"] as? [String:Any],
              let layers=instrument["Layers"] as? [[String:Any]],layers.count<=4096 else{throw ExternalInstrumentError.unsupportedFormat}
        let references=state["file-references"] as? [String:String] ?? [:]
        var zones:[Zone]=[]
        for layer in layers {
            for zone in layer["Zones"] as? [[String:Any]] ?? [] {
                guard zones.count<65536 else{throw ExternalInstrumentError.unsupportedFormat}
                let waveform=zone["waveform"] as? NSNumber
                let reference=waveform.map{"Sample:\($0.int64Value)"} ?? ""
                let sample=references[reference] ?? reference
                zones.append(Zone(id:zones.count,low:max(zone["min key"] as? Int ?? 0,layer["min key"] as? Int ?? 0),high:min(zone["max key"] as? Int ?? 127,layer["max key"] as? Int ?? 127),
                                  velocityLow:max(zone["min vel"] as? Int ?? zone["min velocity"] as? Int ?? 0,layer["min vel"] as? Int ?? 0),velocityHigh:min(zone["max vel"] as? Int ?? zone["max velocity"] as? Int ?? 127,layer["max vel"] as? Int ?? 127),
                                  root:zone["root key"] as? Int ?? 60,sample:zone["name"] as? String ?? URL(fileURLWithPath:sample).lastPathComponent,
                                  looped:(zone["loop enabled"] as? Bool ?? false)))
            }
        }
        return Map(sampleCount:Set(references.values).count,zones:zones,layerCount:layers.count)
    }
    struct Original:Codable,Equatable {
        var file:String
        var sha256:String
    }
    /// Retain the unmodified instrument in addition to the relocated playback
    /// preset. This preserves fields the system's EXS translator cannot expose.
    static func retainOriginal(_ source:URL,library:URL)throws->Original {
        let values=try source.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
        guard values.isRegularFile==true,(values.fileSize ?? Int.max)<=16_000_000 else{throw ExternalInstrumentError.unsupportedFormat}
        let bytes=try Data(contentsOf:source)
        guard bytes.count<=16_000_000,["exs","aupreset"].contains(source.pathExtension.lowercased()) else{throw ExternalInstrumentError.unsupportedFormat}
        let digest=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
        let directory=library.appendingPathComponent("Original Instruments",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let filename=digest+"."+source.pathExtension.lowercased(),target=directory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath:target.path) {
            guard try Data(contentsOf:target)==bytes else{throw CocoaError(.fileReadCorruptFile)}
        } else {try bytes.write(to:target,options:.atomic)}
        return Original(file:"Original Instruments/"+filename,sha256:digest)
    }
}
