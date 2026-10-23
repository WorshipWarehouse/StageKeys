import Foundation
import CryptoKit
import Darwin
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
            if (updated.nativeSampler?.conversionVersion ?? 1)<5 {updated=try updateSplitRegions(updated,original:original,library:library)}
            updated=try updateAmplitudeVelocity(updated,original:original,library:library)
            return try updateResponse(updated,original:original,library:library)
        } catch {
            // A v1→v2 envelope step must not leave disk/metadata out of sync if
            // the following synthesis step rejects a hand-edited filter.
            try previous.write(to:file,options:.atomic)
            throw error
        }
    }
    /// Upgrade only generated gain routes; retain source bytes and user processing.
    static func updateResponse(_ sound:ExternalSound,original:Original,library:URL)throws->ExternalSound {
        guard var program=sound.nativeSampler,(program.conversionVersion ?? 1)<6 else{return sound}
        guard let name=sound.fileName,name==URL(fileURLWithPath:name).lastPathComponent,
              original.sha256.count==64,original.sha256.allSatisfy({$0.isHexDigit}),
              original.file=="Original Instruments/"+original.sha256+".exs" else{throw ExternalInstrumentError.unsupportedFormat}
        let sourceURL=library.appendingPathComponent(original.file)
        guard (try sourceURL.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max)<=16_000_000 else{throw CocoaError(.fileReadTooLarge)}
        let source=try Data(contentsOf:sourceURL)
        guard source.count<=16_000_000,MainStagePatch.digest(source)==original.sha256 else{throw CocoaError(.fileReadCorruptFile)}
        let chunks=try EXSNative.referenceIdentities(EXSNative.chunks(source)),envelope=try EXSNative.envelope(chunks)
        let file=library.appendingPathComponent("Imported Sounds/"+name),bytes=try Data(contentsOf:file)
        guard bytes.count<=16_000_000,var state=try PropertyListSerialization.propertyList(from:bytes,options:[],format:nil) as? [String:Any],
              let metadata=state["StageKeys.NativeSampler"] as? Data,try JSONDecoder().decode(NativeSamplerProgram.self,from:metadata)==program,
              var instrument=state["Instrument"] as? [String:Any],var layers=instrument["Layers"] as? [[String:Any]] else{throw ExternalInstrumentError.unsupportedFormat}
        func u32(_ b:[UInt8],_ p:Int)->Int {(0..<4).reduce(0){$0 | Int(b[p+$1]) << ($1*8)}}
        var notes=Set(program.notes)
        for rule in program.groups {
            let groups=chunks.filter{$0.kind==2 && $0.name==rule.name}
            guard layers.indices.contains(rule.layer),groups.count==1,groups[0].body.count>=92,
                  let zones=layers[rule.layer]["Zones"] as? [[String:Any]] else{throw ExternalInstrumentError.unsupportedFormat}
            let originals=chunks.filter{$0.kind==1 && $0.body.count>=96 && u32($0.body,88)==groups[0].index}
            for zone in zones {
                let matches=originals.filter{$0.name==zone["name"] as? String}
                guard matches.count==1,let gain=(zone["gain"] as? NSNumber)?.doubleValue,
                      abs(gain-(Double(Int8(bitPattern:matches[0].body[4]))+(program.voiceControls?.gain ?? 0)+(program.voiceControls?.amplitudeVelocity?.high ?? 0)))<0.000001 else{
                    throw MainStagePatch.Failure.invalid("The sampler zone gain was edited; import the original EXS separately to preserve those edits.")
                }
            }
            if let amp=program.voiceControls?.amplitudeVelocity {
                let destination=0x50100000+rule.layer*256
                let routes=(layers[rule.layer]["Connections"] as? [[String:Any]] ?? []).filter{($0["source"] as? Int)==301 && ($0["destination"] as? Int)==destination}
                guard routes.count==1,let r=routes.first,r["enabled"] as? Bool==true,
                      ((r["transform"] as? Int==2 && r["inverse"] as? Bool==true && (r["scale"] as? NSNumber)?.doubleValue==amp.sensitivity) ||
                       (r["transform"] as? Int==1 && r["inverse"] as? Bool==false && (r["min value"] as? NSNumber)?.doubleValue==amp.sensitivity*0.5 && (r["max value"] as? NSNumber)?.doubleValue == -amp.sensitivity*0.5/127)) else{
                    throw MainStagePatch.Failure.invalid("The sampler amplitude route was edited; import the original EXS separately to preserve those edits.")
                }
                // The high endpoint is already in these zones; do not add it twice.
                var depth=amp;depth.high=0;EXSNative.applyAmplitudeVelocity(depth,to:&layers[rule.layer])
            }
            if let envelope {
                var expected=layers[rule.layer];EXSNative.applyEnvelope(envelope,group:groups[0].body,to:&expected)
                EXSNative.applyVoiceControls(program.voiceControls,envelope:envelope,group:groups[0].body,to:&expected)
                if NSArray(array:expected["Envelopes"] as? [[String:Any]] ?? [])==NSArray(array:layers[rule.layer]["Envelopes"] as? [[String:Any]] ?? []),
                   var connections=layers[rule.layer]["Connections"] as? [[String:Any]] {
                    let source=0x20000000+rule.layer*256,destination=0x50100000+rule.layer*256
                    for i in connections.indices where connections[i]["source"] as? Int==source && connections[i]["destination"] as? Int==destination {
                        guard connections[i]["enabled"] as? Bool==true,connections[i]["inverse"] as? Bool==true,(connections[i]["scale"] as? NSNumber)?.doubleValue == -96,[1,2].contains(connections[i]["transform"] as? Int ?? 0) else{
                            throw MainStagePatch.Failure.invalid("The sampler envelope gain route was edited; import the original EXS separately to preserve those edits.")
                        }
                        connections[i]["transform"]=2
                    }
                    layers[rule.layer]["Connections"]=connections
                } else{notes.insert("An edited amplitude envelope was preserved; its gain curve was not upgraded.")}
            }
            EXSNative.applyCenterGain(to:&layers[rule.layer])
        }
        notes.insert("Native response v6 translates amplitude velocity half-dB units, MIDI endpoints, the amplitude envelope gain curve and centered output normalization. Original samples and source settings are retained.")
        program.notes=notes.sorted();program.conversionVersion=6;guard program.valid else{throw ExternalInstrumentError.unsupportedFormat}
        instrument["Layers"]=layers;state["Instrument"]=instrument;state["StageKeys.NativeSampler"]=try JSONEncoder().encode(program)
        let backup=library.appendingPathComponent("Sampler Backups",isDirectory:true);try FileManager.default.createDirectory(at:backup,withIntermediateDirectories:true)
        let retained=backup.appendingPathComponent(MainStagePatch.digest(bytes)+".aupreset")
        if !FileManager.default.fileExists(atPath:retained.path){try bytes.write(to:retained,options:.atomic)}
        try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:file,options:.atomic)
        var updated=sound;updated.nativeSampler=program;return updated
    }
    static func updateAmplitudeVelocity(_ sound:ExternalSound,original:Original,library:URL)throws->ExternalSound {
        guard var program=sound.nativeSampler,program.voiceControls?.amplitudeVelocity==nil else{return sound}
        guard let name=sound.fileName,name==URL(fileURLWithPath:name).lastPathComponent,
              original.sha256.count==64,original.sha256.allSatisfy({$0.isHexDigit}),original.file=="Original Instruments/"+original.sha256+".exs" else{throw ExternalInstrumentError.unsupportedFormat}
        let source=try MainStagePatch.read(library.appendingPathComponent(original.file),in:library)
        guard MainStagePatch.digest(source)==original.sha256 else{throw CocoaError(.fileReadCorruptFile)}
        var notes=Set(program.notes)
        guard let amplitude=try EXSNative.voiceControls(EXSNative.chunks(source),notes:&notes)?.amplitudeVelocity else{return sound}
        let file=library.appendingPathComponent("Imported Sounds/"+name),bytes=try Data(contentsOf:file)
        guard bytes.count<=16_000_000,var state=try PropertyListSerialization.propertyList(from:bytes,options:[],format:nil) as? [String:Any],
              let metadata=state["StageKeys.NativeSampler"] as? Data,try JSONDecoder().decode(NativeSamplerProgram.self,from:metadata)==program,
              var instrument=state["Instrument"] as? [String:Any],var layers=instrument["Layers"] as? [[String:Any]] else{throw ExternalInstrumentError.unsupportedFormat}
        for i in layers.indices {
            let destination=0x50100000+(layers[i]["ID"] as? Int ?? 0)*256
            let routes=(layers[i]["Connections"] as? [[String:Any]] ?? []).filter{($0["source"] as? Int)==301 && ($0["destination"] as? Int)==destination}
            guard routes.count==1,let route=routes.first,route["scale"] as? Double == -96,route["transform"] as? Int==2,route["inverse"] as? Bool==true,route["enabled"] as? Bool==true else{throw MainStagePatch.Failure.invalid("The sampler amplitude response was edited; import the original EXS separately to preserve those edits.")}
            EXSNative.applyAmplitudeVelocity(amplitude,to:&layers[i])
        }
        instrument["Layers"]=layers;state["Instrument"]=instrument
        program.voiceControls?.amplitudeVelocity=amplitude;program.notes=notes.sorted()
        state["StageKeys.NativeSampler"]=try JSONEncoder().encode(program)
        let backup=library.appendingPathComponent("Sampler Backups",isDirectory:true);try FileManager.default.createDirectory(at:backup,withIntermediateDirectories:true)
        let retained=backup.appendingPathComponent(MainStagePatch.digest(bytes)+".aupreset");if !FileManager.default.fileExists(atPath:retained.path){try bytes.write(to:retained,options:.atomic)}
        try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:file,options:.atomic)
        var result=sound;result.nativeSampler=program;return result
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

/// Apply the measured host curve as per-velocity zone gain, never as MIDI
/// velocity remapping. Shared sample data, filter/envelope routes and original
/// presets remain unchanged. Call after split-region PCM preparation.
enum SamplerHostVelocity {
    static func gainDB(velocity:Int,curve:Int,sensitivity:Double)->Double {
        let x=Double(min(127,max(0,velocity)))/127,a=Double(abs(curve))/10
        let shaped=curve<0 ? (1+a)*x/(1+a*x):x/(1+a*(1-x))
        return -sensitivity * 0.5 * (shaped-x)
    }
    static func prepare(_ original:[String:Any],curve:Int?)throws->[String:Any] {
        guard let curve,curve != 0 else{return original}
        guard (-20...20).contains(curve) else{throw MainStagePatch.Failure.invalid("Unsupported sampler host velocity curve.")}
        if let previous=original["StageKeys.HostVelocityCurve"] as? Int {
            guard previous==curve else{throw MainStagePatch.Failure.invalid("Reload the original sampler before changing its host velocity curve.")}
            return original
        }
        guard let bytes=original["StageKeys.NativeSampler"] as? Data,
              let program=try? JSONDecoder().decode(NativeSamplerProgram.self,from:bytes),program.valid,
              let amplitude=program.voiceControls?.amplitudeVelocity,amplitude.valid,
              var instrument=original["Instrument"] as? [String:Any],var layers=instrument["Layers"] as? [[String:Any]] else{return original}
        guard amplitude.sensitivity != 0 else{return original}
        var total=0
        for i in layers.indices {
            let layerID=layers[i]["ID"] as? Int ?? i
            guard (0..<64).contains(layerID) else{throw ExternalInstrumentError.unsupportedFormat}
            let destination=0x50100000+layerID*256
            let routes=(layers[i]["Connections"] as? [[String:Any]] ?? []).filter{($0["source"] as? Int)==301 && ($0["destination"] as? Int)==destination}
            guard routes.count==1,let route=routes.first,route["enabled"] as? Bool==true,
                  ((route["inverse"] as? Bool==true && route["transform"] as? Int==2 && (route["scale"] as? NSNumber)?.doubleValue==amplitude.sensitivity) ||
                   (route["inverse"] as? Bool==false && route["transform"] as? Int==1 && (route["min value"] as? NSNumber)?.doubleValue==amplitude.sensitivity*0.5 && (route["max value"] as? NSNumber)?.doubleValue == -amplitude.sensitivity*0.5/127)) else{throw MainStagePatch.Failure.invalid("The sampler amplitude route was edited; its host curve was not applied.")}
            guard let zones=layers[i]["Zones"] as? [[String:Any]] else{continue}
            var expanded:[[String:Any]]=[]
            for zone in zones {
                guard let low=zone["min vel"] as? Int,let high=zone["max vel"] as? Int,(0...127).contains(low),(low...127).contains(high),
                      let gain=(zone["gain"] as? NSNumber)?.doubleValue,gain.isFinite else{throw ExternalInstrumentError.unsupportedFormat}
                for velocity in low...high {
                    total+=1;guard total<=65536 else{throw MainStagePatch.Failure.invalid("Host velocity expansion exceeds the native zone limit.")}
                    var copy=zone;copy["ID"]=expanded.count;copy["min vel"]=velocity;copy["max vel"]=velocity
                    copy["gain"]=gain+gainDB(velocity:velocity,curve:curve,sensitivity:amplitude.sensitivity)
                    expanded.append(copy)
                }
            }
            layers[i]["Zones"]=expanded
        }
        instrument["Layers"]=layers;var state=original;state["Instrument"]=instrument;state["StageKeys.HostVelocityCurve"]=curve;return state
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
    @discardableResult static func load(_ sampler:AVAudioUnitSampler,file:URL,minimum:Float,curve:Int?=nil)throws->[String:Any] {
        let bytes=try Data(contentsOf:file)
        guard bytes.count<=16_000_000,let original=try PropertyListSerialization.propertyList(from:bytes,options:[],format:nil) as? [String:Any] else{throw ExternalInstrumentError.unsupportedFormat}
        let prepared=try SamplerHostVelocity.prepare(SamplerSplitRegions.prepare(prepare(original,minimum:minimum)),curve:curve),temporary=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".aupreset")
        defer{try? FileManager.default.removeItem(at:temporary)}
        try PropertyListSerialization.data(fromPropertyList:prepared,format:.xml,options:0).write(to:temporary)
        try sampler.loadInstrument(at:temporary)
        return prepared
    }
}

/// Repackage discontiguous PCM frames without decoding, resampling or changing
/// their bytes. Original files and saved preset references remain untouched.
enum SamplerSplitRegions {
    private static var cache:[String:URL]=[:]
    private static let directory:URL = {
        let manager=FileManager.default,base=manager.temporaryDirectory
        // Only our PID-marked derived caches are eligible, never source audio.
        for file in (try? manager.contentsOfDirectory(at:base,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey])) ?? [] where file.lastPathComponent.hasPrefix("StageKeys-Regions-p") {
            let suffix=file.lastPathComponent.dropFirst("StageKeys-Regions-p".count)
            guard let pid=Int32(suffix.split(separator:"-").first ?? ""),pid>0,
                  let values=try? file.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey]),values.isDirectory==true,values.isSymbolicLink != true else{continue}
            if kill(pid,0) != 0 && errno==ESRCH {try? manager.removeItem(at:file)}
        }
        let folder=base.appendingPathComponent("StageKeys-Regions-p\(getpid())-"+UUID().uuidString,isDirectory:true)
        atexit {try? FileManager.default.removeItem(at:SamplerSplitRegions.directory)}
        return folder
    }()
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
              stride==channels*(bits/8),flags&32==0 else{throw ExternalInstrumentError.unsupportedFormat}
        // Edited or corrupt region offsets must be rejected here. Data.subdata
        // raises an Objective-C exception instead of throwing, which would end
        // the process on a hostile or damaged preset rather than reporting it.
        let frames=data.count/stride
        guard frames>0,attack.upperBound<=frames,loop.upperBound<=frames else{throw ExternalInstrumentError.unsupportedFormat}
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
    /// One PCM file per source keeps large maps from opening hundreds of files
    /// or exhausting the sampler's waveform/file resources at harder velocities.
    private static func combine(_ files:[URL])throws->URL {
        let key="compound:"+files.map(\.path).joined(separator:"|")
        if let file=cache[key] {return file}
        guard !files.isEmpty else{throw ExternalInstrumentError.unsupportedFormat}
        var total=0,header=Data()
        for (index,file) in files.enumerated() {
            let bytes=try Data(contentsOf:file,options:.mappedIfSafe)
            guard bytes.count>=68 else{throw CocoaError(.fileReadCorruptFile)}
            if index==0 {header=Data(Array(bytes.prefix(68)))}
            else {guard bytes[8..<52]==header[8..<52] else{throw ExternalInstrumentError.unsupportedFormat}}
            total+=bytes.count-68
            guard total<=1_000_000_000 else{throw CocoaError(.fileReadTooLarge)}
        }
        let count=UInt64(total+4)
        for i in 0..<8 {header[56+i]=UInt8(truncatingIfNeeded:count >> ((7-i)*8))}
        let file=directory.appendingPathComponent(UUID().uuidString+".caf")
        guard FileManager.default.createFile(atPath:file.path,contents:header) else{throw CocoaError(.fileWriteUnknown)}
        let handle=try FileHandle(forWritingTo:file);defer{try? handle.close()}
        try handle.seekToEnd()
        for input in files {let bytes=try Data(contentsOf:input,options:.mappedIfSafe);try handle.write(contentsOf:bytes[68...])}
        cache[key]=file;return file
    }
    static func prepare(_ original:[String:Any])throws->[String:Any] {
        guard var instrument=original["Instrument"] as? [String:Any],var layers=instrument["Layers"] as? [[String:Any]],
              var references=original["file-references"] as? [String:String] else{return original}
        struct Region {var layer:Int;var zone:Int;var file:URL;var count:Int;var loop:Int}
        var batches:[String:[Region]]=[:]
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
                batches[path,default:[]].append(Region(layer:l,zone:z,file:file,count:count+tail,loop:count+loopStart-attackEnd))
                for key in ["StageKeys EXS attack end","StageKeys EXS tail start","StageKeys EXS tail end"] {zones[z].removeValue(forKey:key)}
            }
            layers[l]["Zones"]=zones
        }
        guard !batches.isEmpty else{return original}
        for path in batches.keys.sorted() {
            let regions=batches[path]!,file=try combine(regions.map(\.file))
            references["Sample:\(next)"]=file.path
            var offset=0
            for region in regions {
                var zones=layers[region.layer]["Zones"] as! [[String:Any]]
                zones[region.zone]["waveform"]=next;zones[region.zone]["sample start"]=offset
                zones[region.zone]["sample end"]=offset+region.count-1
                zones[region.zone]["loop start"]=offset+region.loop;zones[region.zone]["loop end"]=offset+region.count-1
                layers[region.layer]["Zones"]=zones;offset+=region.count
            }
            next+=1
        }
        let used=Set(layers.flatMap{($0["Zones"] as? [[String:Any]] ?? []).compactMap{$0["waveform"] as? Int}})
        references=references.filter{key,_ in !key.hasPrefix("Sample:") || used.contains(Int(key.dropFirst(7)) ?? -1)}
        instrument["Layers"]=layers;var state=original;state["Instrument"]=instrument;state["file-references"]=references;return state
    }
}
