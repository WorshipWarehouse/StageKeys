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
        var amplitudeEnvelope:EXSNative.Envelope?
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
        let program=(state["StageKeys.NativeSampler"] as? Data).flatMap{try? JSONDecoder().decode(NativeSamplerProgram.self,from:$0)}
        return Map(sampleCount:Set(references.values).count,zones:zones,layerCount:layers.count,amplitudeEnvelope:program?.amplitudeEnvelope)
    }
    /// Upgrade only our untouched v1 envelope reconstruction. Audio, zones,
    /// routing and user rack processing are never rebuilt or replaced.
    static func updateEnvelope(_ sound:ExternalSound,original:Original,library:URL)throws->ExternalSound {
        guard var program=sound.nativeSampler,(program.conversionVersion ?? 1)<2,
              let name=sound.fileName,name==URL(fileURLWithPath:name).lastPathComponent,
              original.sha256.count==64,original.sha256.allSatisfy({$0.isHexDigit}),
              original.file=="Original Instruments/"+original.sha256+".exs" else{throw ExternalInstrumentError.unsupportedFormat}
        let sourceURL=library.appendingPathComponent(original.file)
        guard let sourceSize=try sourceURL.resourceValues(forKeys:[.fileSizeKey]).fileSize,sourceSize<=16_000_000 else{throw ExternalInstrumentError.unsupportedFormat}
        let source=try Data(contentsOf:sourceURL)
        guard MainStagePatch.digest(source)==original.sha256 else{throw CocoaError(.fileReadCorruptFile)}
        let chunks=try EXSNative.chunks(source)
        guard let envelope=try EXSNative.envelope(chunks) else{throw MainStagePatch.Failure.invalid("The retained EXS amplitude envelope is not yet supported.")}
        let preset=library.appendingPathComponent("Imported Sounds/"+name),bytes=try Data(contentsOf:preset)
        guard bytes.count<=16_000_000,var state=try PropertyListSerialization.propertyList(from:bytes,options:[],format:nil) as? [String:Any],
              let metadata=state["StageKeys.NativeSampler"] as? Data,try JSONDecoder().decode(NativeSamplerProgram.self,from:metadata)==program,
              var instrument=state["Instrument"] as? [String:Any],var layers=instrument["Layers"] as? [[String:Any]],layers.count==program.groups.count else{throw ExternalInstrumentError.unsupportedFormat}
        for rule in program.groups {
            guard layers.indices.contains(rule.layer),let group=chunks.first(where:{$0.kind==2 && $0.name==rule.name}),group.body.count>=92 else{throw ExternalInstrumentError.unsupportedFormat}
            var expected=layers[rule.layer];EXSNative.applyEnvelope(nil,group:group.body,to:&expected)
            // A hand-edited envelope must not be overwritten by an upgrade.
            guard let old=layers[rule.layer]["Envelopes"] as? NSArray,let generated=expected["Envelopes"] as? NSArray,old==generated else{throw MainStagePatch.Failure.invalid("This sampler's envelope was edited; import the original EXS again to keep those edits separate.")}
            EXSNative.applyEnvelope(envelope,group:group.body,to:&layers[rule.layer])
        }
        instrument["Layers"]=layers;state["Instrument"]=instrument
        program.conversionVersion=2;program.amplitudeEnvelope=envelope
        program.notes.removeAll{$0.contains("Global filter/modulation and envelope mappings") || $0.contains("group envelope release offset")}
        program.notes.append("EXS amplitude attack, decay, sustain and release now use the source time curve. Velocity-dependent attack, envelope shape and global filter/modulation remain approximate/unmapped.")
        guard program.valid else{throw ExternalInstrumentError.unsupportedFormat}
        state["StageKeys.NativeSampler"]=try JSONEncoder().encode(program)
        let backup=library.appendingPathComponent("Sampler Backups",isDirectory:true)
        try FileManager.default.createDirectory(at:backup,withIntermediateDirectories:true)
        let retained=backup.appendingPathComponent(MainStagePatch.digest(bytes)+".aupreset")
        if !FileManager.default.fileExists(atPath:retained.path){try bytes.write(to:retained,options:.atomic)}
        try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:preset,options:.atomic)
        var updated=sound;updated.nativeSampler=program;return updated
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
