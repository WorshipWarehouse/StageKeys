import Foundation
import CryptoKit
import AVFoundation

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
    static func updatePlayback(_ sound:ExternalSound,original:Original,library:URL)throws->ExternalSound {
        guard let name=sound.fileName,name==URL(fileURLWithPath:name).lastPathComponent else{throw ExternalInstrumentError.unsupportedFormat}
        let file=library.appendingPathComponent("Imported Sounds/"+name)
        guard let size=try file.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<=16_000_000 else{throw ExternalInstrumentError.unsupportedFormat}
        let previous=try Data(contentsOf:file)
        do {
            var updated=sound
            if (updated.nativeSampler?.conversionVersion ?? 1)<2 {updated=try updateEnvelope(updated,original:original,library:library)}
            if (updated.nativeSampler?.conversionVersion ?? 1)<3 {updated=try updateVoiceControls(updated,original:original,library:library)}
            return try updateSplitRegions(updated,original:original,library:library)
        } catch {
            // A v1→v2 envelope step must not leave disk/metadata out of sync if
            // the following synthesis step rejects a hand-edited filter.
            try previous.write(to:file,options:.atomic)
            throw error
        }
    }
    /// Add supported source synthesis to an existing generated map, retaining
    /// every zone boundary, sample reference, user rack and existing envelope edit.
    static func updateVoiceControls(_ sound:ExternalSound,original:Original,library:URL)throws->ExternalSound {
        guard var program=sound.nativeSampler,(program.conversionVersion ?? 1)==2,program.voiceControls==nil,
              let name=sound.fileName,name==URL(fileURLWithPath:name).lastPathComponent,
              original.sha256.count==64,original.sha256.allSatisfy({$0.isHexDigit}),
              original.file=="Original Instruments/"+original.sha256+".exs" else{throw ExternalInstrumentError.unsupportedFormat}
        let sourceURL=library.appendingPathComponent(original.file)
        guard let size=try sourceURL.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<=16_000_000 else{throw ExternalInstrumentError.unsupportedFormat}
        let source=try Data(contentsOf:sourceURL)
        guard MainStagePatch.digest(source)==original.sha256 else{throw CocoaError(.fileReadCorruptFile)}
        let chunks=try EXSNative.chunks(source),envelope=try EXSNative.envelope(chunks)
        var notes=Set(program.notes.filter{!$0.contains("global filter/modulation remain unmapped") && !$0.contains("global filter/modulation remain approximate/unmapped") && !$0.contains("Velocity-dependent attack, envelope shape and global filter/modulation")})
        let controls=try EXSNative.voiceControls(chunks,notes:&notes)
        let preset=library.appendingPathComponent("Imported Sounds/"+name),bytes=try Data(contentsOf:preset)
        guard bytes.count<=16_000_000,var state=try PropertyListSerialization.propertyList(from:bytes,options:[],format:nil) as? [String:Any],
              let metadata=state["StageKeys.NativeSampler"] as? Data,try JSONDecoder().decode(NativeSamplerProgram.self,from:metadata)==program,
              var instrument=state["Instrument"] as? [String:Any],var layers=instrument["Layers"] as? [[String:Any]],layers.count==program.groups.count else{throw ExternalInstrumentError.unsupportedFormat}
        for rule in program.groups {
            guard layers.indices.contains(rule.layer),chunks.filter({$0.kind==2 && $0.name==rule.name}).count==1,
                  let group=chunks.first(where:{$0.kind==2 && $0.name==rule.name}),group.body.count>=92,
                  let filter=layers[rule.layer]["Filters"] as? [String:Any],filter["enabled"] as? Bool==false,
                  !(layers[rule.layer]["Connections"] as? [[String:Any]] ?? []).contains(where:{ (($0["destination"] as? Int ?? 0)&0xffff00ff)==EXSNative.cutoffDestination }) else {
                throw MainStagePatch.Failure.invalid("The sampler filter was edited; import the original EXS separately to keep those edits.")
            }
            var expected=layers[rule.layer];EXSNative.applyEnvelope(envelope,group:group.body,to:&expected)
            let unchanged=NSArray(array:expected["Envelopes"] as? [[String:Any]] ?? [])==NSArray(array:layers[rule.layer]["Envelopes"] as? [[String:Any]] ?? [])
            if !unchanged {notes.insert("An edited amplitude envelope was preserved; velocity-dependent attack was not applied to that layer.")}
            EXSNative.applyVoiceControls(controls,envelope:unchanged ? envelope:nil,group:group.body,to:&layers[rule.layer])
        }
        instrument["Layers"]=layers;state["Instrument"]=instrument
        program.voiceControls=controls;program.conversionVersion=3;program.notes=notes.sorted()
        guard program.valid else{throw ExternalInstrumentError.unsupportedFormat}
        state["StageKeys.NativeSampler"]=try JSONEncoder().encode(program)
        let backup=library.appendingPathComponent("Sampler Backups",isDirectory:true)
        try FileManager.default.createDirectory(at:backup,withIntermediateDirectories:true)
        let retained=backup.appendingPathComponent(MainStagePatch.digest(bytes)+".aupreset")
        if !FileManager.default.fileExists(atPath:retained.path){try bytes.write(to:retained,options:.atomic)}
        try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:preset,options:.atomic)
        var updated=sound;updated.nativeSampler=program;return updated
    }
    /// Repair only generated split-region maps; preserve envelopes, filters and effects.
    static func updateSplitRegions(_ sound:ExternalSound,original:Original,library:URL)throws->ExternalSound {
        guard var program=sound.nativeSampler,[3,4].contains(program.conversionVersion ?? 0),
              let name=sound.fileName,name==URL(fileURLWithPath:name).lastPathComponent,
              original.sha256.count==64,original.sha256.allSatisfy({$0.isHexDigit}),
              original.file=="Original Instruments/"+original.sha256+".exs" else{throw ExternalInstrumentError.unsupportedFormat}
        let sourceFile=library.appendingPathComponent(original.file)
        guard let sourceSize=try sourceFile.resourceValues(forKeys:[.fileSizeKey]).fileSize,sourceSize<=16_000_000 else{throw ExternalInstrumentError.unsupportedFormat}
        let source=try Data(contentsOf:sourceFile)
        guard source.count<=16_000_000,MainStagePatch.digest(source)==original.sha256 else{throw CocoaError(.fileReadCorruptFile)}
        let chunks=try EXSNative.chunks(source)
        let file=library.appendingPathComponent("Imported Sounds/"+name),bytes=try Data(contentsOf:file)
        guard bytes.count<=16_000_000,var state=try PropertyListSerialization.propertyList(from:bytes,options:[],format:nil) as? [String:Any],
              let metadata=state["StageKeys.NativeSampler"] as? Data,try JSONDecoder().decode(NativeSamplerProgram.self,from:metadata)==program,
              var instrument=state["Instrument"] as? [String:Any],var layers=instrument["Layers"] as? [[String:Any]] else{throw ExternalInstrumentError.unsupportedFormat}
        func u32(_ b:[UInt8],_ p:Int)->Int {(0..<4).reduce(0){$0 | Int(b[p+$1]) << ($1*8)}}
        for rule in program.groups {
            let groups=chunks.filter{$0.kind==2 && $0.name==rule.name}
            guard groups.count==1,layers.indices.contains(rule.layer),var zones=layers[rule.layer]["Zones"] as? [[String:Any]] else{throw ExternalInstrumentError.unsupportedFormat}
            let originals=chunks.filter{$0.kind==1 && $0.body.count>=96 && u32($0.body,88)==groups[0].index}
            for i in zones.indices {
                let matching=originals.filter{$0.name==zones[i]["name"] as? String && u32($0.body,12)==zones[i]["sample start"] as? Int}
                guard matching.count==1 else{throw MainStagePatch.Failure.invalid("The sample map was edited; import the original EXS separately to preserve those edits.")}
                let z=matching[0].body,start=u32(z,12),end=u32(z,16),loopStart=u32(z,20),loopEnd=u32(z,24)
                if z[33]&1 != 0 && loopStart>end {
                    guard let waveform=zones[i]["waveform"] as? Int,waveform==0x10000000+u32(z,92),
                          let refs=state["file-references"] as? [String:String],let path=refs["Sample:\(waveform)"],path.hasPrefix("/") else{throw ExternalInstrumentError.unsupportedFormat}
                    let length=try AVAudioFile(forReading:URL(fileURLWithPath:path)).length
                    let boundedEnd=min(loopEnd,Int(length)-1)
                    guard zones[i]["sample start"] as? Int==start,zones[i]["sample end"] as? Int==boundedEnd,
                          zones[i]["loop start"] as? Int==loopStart,zones[i]["loop end"] as? Int==boundedEnd,
                          zones[i]["loop enabled"] as? Bool==true else{throw MainStagePatch.Failure.invalid("The split sample region was edited; import the original EXS separately.")}
                    guard z.count>=124 else{throw ExternalInstrumentError.unsupportedFormat}
                    let tailStart=u32(z,116),tailEnd=u32(z,120)
                    guard tailEnd>tailStart,tailEnd<=length,tailEnd-tailStart==loopEnd-end else{throw MainStagePatch.Failure.invalid("Invalid EXS separate tail storage.")}
                    zones[i]["StageKeys EXS attack end"]=end
                    zones[i]["StageKeys EXS tail start"]=tailStart;zones[i]["StageKeys EXS tail end"]=tailEnd
                    zones[i]["sample end"]=loopEnd;zones[i]["loop end"]=loopEnd
                }
            }
            layers[rule.layer]["Zones"]=zones
        }
        instrument["Layers"]=layers;state["Instrument"]=instrument
        program.conversionVersion=5
        program.notes.removeAll{$0.contains("Consolidated attack and loop-tail extents")}
        program.notes.append("Separate EXS attack and loop regions use lossless PCM frame assembly at playback; intervening consolidated audio is excluded. Transition interpolation remains engine dependent.")
        guard program.valid else{throw ExternalInstrumentError.unsupportedFormat}
        state["StageKeys.NativeSampler"]=try JSONEncoder().encode(program)
        let backup=library.appendingPathComponent("Sampler Backups",isDirectory:true)
        try FileManager.default.createDirectory(at:backup,withIntermediateDirectories:true)
        let retained=backup.appendingPathComponent(MainStagePatch.digest(bytes)+".aupreset")
        if !FileManager.default.fileExists(atPath:retained.path){try bytes.write(to:retained,options:.atomic)}
        try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:file,options:.atomic)
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

/// Playback-only amplitude attack adjustment. Never edits presets or samples on disk.
enum SamplerAttack {
    static func prepare(_ original:[String:Any],minimum:Float)->[String:Any] {
        guard minimum.isFinite,minimum>0,minimum<=0.1,
              var instrument=original["Instrument"] as? [String:Any],var layers=instrument["Layers"] as? [[String:Any]] else{return original}
        for i in layers.indices {
            let layerID=layers[i]["ID"] as? Int ?? i
            var connections=layers[i]["Connections"] as? [[String:Any]] ?? []
            guard var envelopes=layers[i]["Envelopes"] as? [[String:Any]] else{continue}
            for j in envelopes.indices {
                let envelopeID=envelopes[j]["ID"] as? Int ?? j
                let source=0x20000000+layerID*256+envelopeID
                // Leave filter/pitch envelopes and disabled/non-amplitude routes alone.
                guard envelopes[j]["enabled"] as? Bool != false,connections.contains(where:{($0["source"] as? Int)==source && (($0["destination"] as? Int ?? 0)&0xfff00000)==0x50100000 && $0["enabled"] as? Bool != false}),
                      var stages=envelopes[j]["Stages"] as? [[String:Any]] else{continue}
                for k in stages.indices where (stages[k]["stage"] as? NSNumber)?.doubleValue == 1 {
                    guard let time=stages[k]["time"] as? Double,time.isFinite,time>=0 else{continue}
                    stages[k]["time"]=max(time,Double(minimum))
                }
                envelopes[j]["Stages"]=stages
                // An explicit smoothing minimum overrides the generated velocity
                // factor; otherwise hard notes could scale the minimum back to zero.
                let factor=0x23e00000+layerID*256+envelopeID
                connections.removeAll{($0["source"] as? Int)==301 && ($0["destination"] as? Int)==factor}
            }
            layers[i]["Connections"]=connections
            layers[i]["Envelopes"]=envelopes
        }
        instrument["Layers"]=layers;var state=original;state["Instrument"]=instrument;return state
    }
    static func load(_ sampler:AVAudioUnitSampler,file:URL,minimum:Float)throws {
        let bytes=try Data(contentsOf:file)
        guard bytes.count<=16_000_000,let original=try PropertyListSerialization.propertyList(from:bytes,options:[],format:nil) as? [String:Any] else{throw ExternalInstrumentError.unsupportedFormat}
        let prepared=try SamplerSplitRegions.prepare(prepare(original,minimum:minimum)),temporary=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".aupreset")
        defer{try? FileManager.default.removeItem(at:temporary)}
        try PropertyListSerialization.data(fromPropertyList:prepared,format:.xml,options:0).write(to:temporary)
        try sampler.loadInstrument(at:temporary)
    }
}

/// Repackage discontiguous PCM frames without decoding, resampling or changing
/// their bytes. Original files and saved preset references remain untouched.
enum SamplerSplitRegions {
    private static var cache:[String:URL]=[:]
    private static let directory=FileManager.default.temporaryDirectory.appendingPathComponent("StageKeys-Regions-"+UUID().uuidString,isDirectory:true)
    static func assemble(_ source:URL,attack:Range<Int>,loop:Range<Int>)throws->URL {
        let info=try source.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey,.isRegularFileKey])
        guard info.isRegularFile==true,let size=info.fileSize,size<=1_000_000_000,
              attack.lowerBound>=0,!attack.isEmpty,!loop.isEmpty,loop.lowerBound>=0 else{throw ExternalInstrumentError.unsupportedFormat}
        let key="\(source.path):\(size):\(info.contentModificationDate?.timeIntervalSince1970 ?? 0):\(attack):\(loop)"
        if let existing=cache[key]{return existing}
        let bytes=try Data(contentsOf:source,options:.mappedIfSafe)
        func be(_ p:Int,_ n:Int)->UInt64 {bytes[p..<p+n].reduce(0){($0<<8)|UInt64($1)}}
        guard bytes.count>=8,String(data:bytes[0..<4],encoding:.ascii)=="caff",be(4,2)==1 else{throw MainStagePatch.Failure.invalid("Split EXS regions currently require uncompressed PCM CAF samples.")}
        var pos=8,description:Data?,pcm:Range<Int>?
        while pos+12<=bytes.count {
            let type=String(data:bytes[pos..<pos+4],encoding:.ascii),length=be(pos+4,8)
            let begin=pos+12
            guard length<=UInt64(bytes.count-begin) else{throw CocoaError(.fileReadCorruptFile)}
            let end=begin+Int(length)
            if type=="desc" {guard description==nil,length==32 else{throw CocoaError(.fileReadCorruptFile)};description=bytes.subdata(in:begin..<end)}
            if type=="data" {guard pcm==nil,length>=4 else{throw CocoaError(.fileReadCorruptFile)};pcm=(begin+4)..<end}
            pos=end
        }
        guard let desc=description,let data=pcm,String(data:desc[8..<12],encoding:.ascii)=="lpcm" else{throw ExternalInstrumentError.unsupportedFormat}
        func dbe(_ p:Int)->Int {desc[p..<p+4].reduce(0){($0<<8)|Int($1)}}
        let stride=dbe(16),framesPerPacket=dbe(20),channels=dbe(24),bits=dbe(28),flags=dbe(12)
        guard framesPerPacket==1,(1...8).contains(channels),[8,16,24,32,64].contains(bits),
              stride==channels*(bits/8),flags&32==0,loop.upperBound<=data.count/stride else{throw ExternalInstrumentError.unsupportedFormat}
        let total=attack.count+loop.count
        guard total<=Int(Int32.max),total*stride<=256_000_000 else{throw ExternalInstrumentError.unsupportedFormat}
        var output=Data("caff".utf8);output.append(contentsOf:[0,1,0,0])
        func integer(_ value:UInt64){for shift in Swift.stride(from:56,through:0,by:-8){output.append(UInt8(truncatingIfNeeded:value>>shift))}}
        output.append(Data("desc".utf8));integer(32);output.append(desc)
        output.append(Data("data".utf8));integer(UInt64(total*stride+4));output.append(contentsOf:[0,0,0,0])
        for range in [attack,loop] {output.append(bytes.subdata(in:(data.lowerBound+range.lowerBound*stride)..<(data.lowerBound+range.upperBound*stride)))}
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let file=directory.appendingPathComponent(UUID().uuidString+".caf")
        try output.write(to:file,options:.atomic);cache[key]=file;return file
    }
    static func prepare(_ original:[String:Any])throws->[String:Any] {
        guard var instrument=original["Instrument"] as? [String:Any],var layers=instrument["Layers"] as? [[String:Any]],
              var references=original["file-references"] as? [String:String] else{return original}
        var next=(references.keys.compactMap{Int($0.replacingOccurrences(of:"Sample:",with:""))}.max() ?? 0x10000000)+1
        for l in layers.indices {
            guard var zones=layers[l]["Zones"] as? [[String:Any]] else{continue}
            for z in zones.indices {
                guard let attackEnd=zones[z]["StageKeys EXS attack end"] as? Int else{continue}
                guard let start=zones[z]["sample start"] as? Int,let loopStart=zones[z]["loop start"] as? Int,
                      let loopEnd=zones[z]["loop end"] as? Int,let waveform=zones[z]["waveform"] as? Int,
                      let path=references["Sample:\(waveform)"],path.hasPrefix("/"),
                      start<attackEnd,attackEnd<loopStart,loopStart<loopEnd else{throw ExternalInstrumentError.unsupportedFormat}
                guard let tailStart=zones[z]["StageKeys EXS tail start"] as? Int,
                      let tailEnd=zones[z]["StageKeys EXS tail end"] as? Int,
                      tailStart>=0,tailEnd>tailStart,tailEnd-tailStart==loopEnd-attackEnd else{throw MainStagePatch.Failure.invalid("Missing EXS separate tail mapping; update converted sampler playback.")}
                let file=try assemble(URL(fileURLWithPath:path),attack:start..<attackEnd,loop:tailStart..<tailEnd)
                let count=attackEnd-start,tail=tailEnd-tailStart
                references["Sample:\(next)"]=file.path;zones[z]["waveform"]=next;next+=1
                zones[z]["sample start"]=0;zones[z]["sample end"]=count+tail-1
                zones[z]["loop start"]=count+loopStart-attackEnd;zones[z]["loop end"]=count+tail-1
                for key in ["StageKeys EXS attack end","StageKeys EXS tail start","StageKeys EXS tail end"] {zones[z].removeValue(forKey:key)}
            }
            layers[l]["Zones"]=zones
        }
        instrument["Layers"]=layers;var state=original;state["Instrument"]=instrument;state["file-references"]=references;return state
    }
}
