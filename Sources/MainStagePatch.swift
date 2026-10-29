import Foundation
import CryptoKit

/// Reads documents as data. Never instantiates archived Objective-C classes,
/// executes MIDI scripts, launches MainStage, or substitutes a synth sound.
enum MainStagePatch {
    /// The document a PSDD record wraps: component identity, a parameter cache and,
    /// for JUCE-based plug-ins, the vendor's own preset bank. Only the wrapper is read;
    /// no plug-in is loaded, no state is applied and no vendor code is executed.
    struct PluginState:Codable,Equatable {
        var presetName:String?
        var componentType:String?
        var componentSubtype:String?
        var manufacturer:String?
        var version:Int?
        var stateBytes:Int
        var stateMagic:String?
        var programCount:Int?
        var identity:String? {
            guard let componentType else{return nil}
            return [componentType,componentSubtype,manufacturer].compactMap{$0}.joined(separator:"/")
        }
        var summary:String {
            var parts:[String]=[]
            if let presetName,presetName != "" {parts.append("preset \"\(presetName)\"")}
            if let programCount,programCount>0 {parts.append("\(programCount)-program bank")}
            parts.append(stateBytes>0 ? "\(stateBytes) bytes" : "no vendor state")
            return parts.joined(separator:", ")
        }
    }
    struct Device:Codable,Equatable {
        var name:String
        var offset:Int
        var byteCount:Int
        var format:String
        /// Saved Audio Unit component identity when the record is a plug-in state.
        var audioUnitType:String? = nil
        var audioUnitSubtype:String? = nil
        var pluginState:PluginState? = nil
        var audioUnitIdentity:String? {
            guard let audioUnitType else{return nil}
            guard let audioUnitSubtype else{return audioUnitType}
            return audioUnitType+"/"+audioUnitSubtype
        }
    }
    struct Channel:Codable,Equatable {
        var name:String
        var file:String
        var sha256:String
        var instruments:[String]
        var devices:[Device]
        var hasMappings:Bool
        var hasMIDIState:Bool
        var nativeInstrumentStatus: String {
            if let family = unsupportedInstrumentFamily {
                return "Archive only: \(family) has no native StageKeys engine. Use an installed compatible AU or retain the source."
            }
            if let unit = thirdPartyAudioUnits.first {
                let identity = unit.audioUnitIdentity.map{" (\($0))"} ?? ""
                // Saved state is MainStage's plug-in blob; an installed Audio Unit alone
                // does not reproduce it, and the saved version may differ from a newer install.
                var base = "Third-party Audio Unit \(unit.name)\(identity): hosted with its saved state when that component is installed. The state is restored, not translated."
                if !instruments.isEmpty {base += " The referenced sampler can be converted, but one layer hosts one instrument, so a converted sampler layer keeps that state in the archive."}
                return unit.pluginState.map{base+" Saved state: \($0.summary)."} ?? base
            }
            return instruments.isEmpty ? "Archive only: no supported sampler reference identified." : "Sampler candidate: original EXS and samples required; processing compatibility must be reviewed."
        }
        var unsupportedInstrumentFamily: String? {
            for device in devices {
                let name = device.name.lowercased().filter { $0.isLetter || $0.isNumber }
                if let family = ["es2":"ES2", "retrosynth":"Retro Synth", "retrosyn":"Retro Synth",
                                 "sculpture":"Sculpture", "sculpt":"Sculpture", "alchemy":"Alchemy"] [name] { return family }
            }
            return nil
        }
        /// Plug-in state records. Their saved state is never translated, so telling the
        /// user which Audio Unit a channel needs is part of the import report.
        var thirdPartyAudioUnits:[Device] { devices.filter{$0.format=="PSDD"} }
        /// A channel can be converted when its sampler can be located or its saved Audio
        /// Unit is installed. Whether the component is actually present is decided later.
        var isConvertible:Bool { !instruments.isEmpty || !thirdPartyAudioUnits.isEmpty }
    }
    struct Report:Codable,Equatable {
        var version=1
        var sourceArchiveID:String?
        var name:String
        var channels:[Channel]
        var blockers:[String]
        var preservedFiles:[String:String]
        var complete:Bool {blockers.isEmpty}
    }
    enum Failure:LocalizedError {
        case invalid(String)
        var errorDescription:String? {if case .invalid(let message)=self{return message};return nil}
    }
    /// Channel metadata carries fader/pan/ranges independently of CST bytes.
    /// Include its verified digest and channel filename so edited settings and
    /// identical strips in distinct channels cannot reuse an unrelated sound.
    static func conversionID(_ report:Report,channel:Channel,variant:String)throws->String {
        guard let metadata=report.preservedFiles["data.plist"] else {
            throw Failure.invalid("The source patch has no metadata integrity record. Import it again before converting.")
        }
        let context=digest(Data((metadata+"/"+channel.file).utf8))
        return "mainstage-channel-"+channel.sha256+"-v2-"+context+"-"+variant
    }
    static func assembledChannels(_ report:Report,entries:[LibrarySound])throws->Patch {
        let channels=report.channels.filter{!$0.instruments.isEmpty || !$0.thirdPartyAudioUnits.isEmpty}
        guard let archive=report.sourceArchiveID,!channels.isEmpty,channels.count<=15 else {
            throw Failure.invalid("Choose a source patch with 1–15 converted instrument channels. More complex patch routing requires manual setup.")
        }
        var layers:[Layer]=[],notes=["Converted channel strips only. Patch-level buses/sends, tempo, scripts and routing require review; this is not full MainStage topology parity."]
        for channel in channels {
            let matches=entries.filter{$0.sourceArchiveID==archive && $0.id.hasPrefix("mainstage-channel-"+channel.sha256+"-")}
            guard matches.count==1,let entry=matches.first,var layer=entry.layer,
                  let kind=layer.external?.kind,kind == .samplerPreset || kind == .audioUnit else {
                throw Failure.invalid("\(channel.name): convert the channel first and resolve multiple converted versions before assembling this patch.")
            }
            layer.id=UUID();layer.name=channel.name;layers.append(layer)
            notes += (entry.conversionNotes ?? []).map{channel.name+": "+$0}
        }
        layers += (layers.count..<15).map{_ in Layer.empty()}
        var patch=Patch(name:String(report.name.prefix(180))+" · Converted",layers:layers,snapshots:[])
        patch.conversionNotes=Array((notes+report.blockers).prefix(128)).map{String($0.prefix(2000))}
        var validation=Setlist();validation.patches=[patch];try validation.validate()
        return patch
    }
    static func digest(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    private static func contained(_ file:URL,in root:URL)->Bool {
        file.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root.resolvingSymlinksInPath().standardizedFileURL.path+"/")
    }
    static func read(_ file:URL,in root:URL)throws->Data {
        guard contained(file,in:root) else{throw Failure.invalid("A patch reference leaves the selected patch folder.")}
        let values=try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard values.isRegularFile==true,values.isSymbolicLink != true,(values.fileSize ?? Int.max)<=16_000_000 else{throw Failure.invalid("Invalid or oversized MainStage document.")}
        let data=try Data(contentsOf:file)
        guard data.count<=16_000_000 else{throw Failure.invalid("Oversized MainStage document.")}
        return data
    }
    static func verifiedRead(_ file:URL,in root:URL,sha256:String?)throws->Data {
        let data=try read(file,in:root)
        guard let sha256,digest(data)==sha256 else{throw Failure.invalid("The retained MainStage source changed or has no integrity record. Import the original patch again before converting.")}
        return data
    }
    static func devices(_ data:Data)throws->[Device] {
        guard data.count>=36,data.prefix(4)==Data("OCuA".utf8) else{throw Failure.invalid("Unsupported channel-strip version; original bytes will not be treated as a sampler preset.")}
        let bytes=[UInt8](data)
        func u32(_ start:Int)->Int {(0..<4).reduce(0){$0 | Int(bytes[start+$1]) << ($1*8)}}
        /// Four-character codes are stored little-endian in this container.
        func fourCC(_ start:Int)->String? {
            guard start>=0,start+4<=bytes.count else{return nil}
            let characters=bytes[start..<start+4]
            guard characters.allSatisfy({(32...126).contains($0)}) else{return nil}
            return String(bytes:characters.reversed(),encoding:.ascii)
        }
        func state(in record:Data)->PluginState? {MainStagePatch.pluginState(in:record)}
        // Observed container signatures: GAME is a built-in processor, MELC the sampler
        // host, PSDD a saved Audio Unit. Arbitrary bytes often spell UCuA by accident, so
        // an unknown signature is still skipped rather than reported as a device.
        var found:[Device]=[],position=0
        while position+172<=bytes.count {
            defer{position+=1}
            guard Array(bytes[position..<position+4])==Array("UCuA".utf8) else{continue}
            let start=position+28,size=u32(start)
            guard size>=144,size<=bytes.count-start-8 else{continue}
            guard let signature=String(bytes:bytes[start+140..<start+144],encoding:.ascii),
                  signature=="GAME" || signature=="MELC" || signature=="PSDD" else{continue}
            let nameBytes=bytes[start+128..<start+140].prefix(while:{$0 != 0})
            guard !nameBytes.isEmpty,nameBytes.allSatisfy({(32...126).contains($0)}),let name=String(bytes:nameBytes,encoding:.ascii) else{continue}
            guard found.count<128 else{throw Failure.invalid("Too many channel-strip devices.")}
            let type=signature=="PSDD" ? fourCC(start+144) : nil
            let subtype=signature=="PSDD" ? fourCC(start+148) : nil
            let audioUnit=type?.hasPrefix("au")==true ? type : nil
            var device=Device(name:name,offset:position,byteCount:size+36,format:signature,
                              audioUnitType:audioUnit,audioUnitSubtype:audioUnit == nil ? nil:subtype)
            if signature=="PSDD" {
                device.pluginState=state(in:Data(bytes[position..<min(bytes.count,position+size+36)]))
            }
            found.append(device)
            position=start+size+7
        }
        return found
    }
    static func instrumentReferences(_ data:Data)->[String] {
        // Observed EXS24 records prefix the saved basename with this signature.
        let marker=Data("MELCPMAS1MAS".utf8)
        var names:[String]=[],start=data.startIndex
        while start<data.endIndex,let range=data.range(of:marker,in:start..<data.endIndex) {
            let suffix=data[range.upperBound..<min(data.endIndex,range.upperBound+256)].prefix(while:{$0 != 0})
            if let name=String(data:suffix,encoding:.utf8),name.lowercased().hasSuffix(".exs"),name==URL(fileURLWithPath:name).lastPathComponent {names.append(name)}
            start=range.upperBound
        }
        return Array(Set(names)).sorted()
    }
    /// Host-only sampler state is not included in the referenced EXS file.
    /// Read bounded parameter pairs inside sampler devices, never arbitrary archive bytes.
    static func amplitudeVelocityCurve(_ data:Data,devices:[Device])throws->Int? {
        var curves=Set<Int>()
        let marker=Data("MELCPMAS1MAS".utf8)
        func integer(_ offset:Int)->Int {
            Int(Int32(bitPattern:(0..<4).reduce(UInt32(0)){$0 | UInt32(data[offset+$1]) << ($1*8)}))
        }
        for device in devices where device.format == "MELC" {
            let end=min(data.count,device.offset+device.byteCount)
            var position=device.offset
            while position<end,let range=data.range(of:marker,in:position..<end) {
                position=range.upperBound
                let nameEnd=min(end,range.lowerBound+76)
                let name=data[range.upperBound..<nameEnd].prefix(while:{$0 != 0})
                guard let filename=String(data:name,encoding:.utf8),filename.lowercased().hasSuffix(".exs"),filename==URL(fileURLWithPath:filename).lastPathComponent else{continue}
                var seen=Set<Int>(),offset=range.lowerBound+76
                for _ in 0..<512 {
                    guard offset+8<=end else{break}
                    let key=integer(offset),value=integer(offset+4)
                    guard key>0,key<=0x10000,seen.insert(key).inserted else{break}
                    if key==0x183 {
                        guard (-20...20).contains(value) else{throw Failure.invalid("Sampler amplitude velocity curve exceeds the supported source range.")}
                        curves.insert(value)
                    }
                    offset+=8
                }
            }
        }
        guard curves.count<=1 else{throw Failure.invalid("Conflicting sampler amplitude velocity curves; select a single instrument channel.")}
        return curves.first
    }
    static func findSamplerInstruments(_ names:Set<String>,in folder:URL)throws->[URL] {
        guard !names.isEmpty,names.count<=64 else{throw Failure.invalid("Invalid instrument reference list.")}
        guard let files=FileManager.default.enumerator(at:folder,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey]) else{throw Failure.invalid("Could not read the selected instrument folder.")}
        var result:[URL]=[],visited=0
        for case let file as URL in files {
            visited+=1;guard visited<=100_000 else{throw Failure.invalid("The selected folder contains too many files; choose a narrower instrument/sample folder.")}
            if files.level>24{files.skipDescendants();continue}
            let attributes=try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
            if attributes.isSymbolicLink==true{files.skipDescendants();continue}
            if attributes.isRegularFile==true,file.pathExtension.lowercased()=="exs",names.contains(file.lastPathComponent) {
                result.append(file);guard result.count<=128 else{throw Failure.invalid("Too many duplicate instrument references.")}
            }
        }
        return result
    }
    private static func fourCC(_ value:Int)->String? {
        let bytes=(0..<4).map{UInt8((value >> (24-$0*8)) & 255)}
        guard bytes.allSatisfy({(32...126).contains($0)}) else{return nil}
        return String(bytes:bytes,encoding:.ascii)
    }
    /// The wrapper document itself, bounded. It is the Audio Unit class-info dictionary
    /// MainStage stored, so it can be applied later without being interpreted here.
    static func pluginStateValues(in record:Data)->[String:Any]? {
        let xml=record.range(of:Data("<?xml".utf8)),binary=record.range(of:Data("bplist00".utf8))
        let origins=[xml?.lowerBound,binary?.lowerBound].compactMap{$0}.sorted()
        guard let origin=origins.first else{return nil}
        let end:Data.Index
        if xml?.lowerBound==origin {
            guard let close=record.range(of:Data("</plist>".utf8),in:origin..<record.endIndex)?.upperBound else{return nil}
            end=close
        } else {end=record.endIndex}
        guard end>origin,end-origin<=8_000_000 else{return nil}
        return try? PropertyListSerialization.propertyList(from:record.subdata(in:origin..<end),options:[],format:nil) as? [String:Any]
    }
    /// Persistable form of the stored class info, matching the Audio Unit restore limit.
    static func pluginStateData(in record:Data)->Data? {
        guard let values=pluginStateValues(in:record),
              let data=try? PropertyListSerialization.data(fromPropertyList:values,format:.binary,options:0),
              data.count<=2_000_000 else{return nil}
        return data
    }
    /// Read the plug-in-state wrapper inside a PSDD record. The vendor payload is only
    /// measured and counted; its contents are never interpreted as code or applied.
    static func pluginState(in record:Data)->PluginState? {
        guard let values=pluginStateValues(in:record) else{return nil}
        func number(_ key:String)->Int? {(values[key] as? NSNumber).map{$0.intValue}}
        let vendor=values["jucePluginState"] as? Data
        let magic=vendor.flatMap{payload->String? in
            let head=payload.prefix(4)
            guard head.count==4,head.allSatisfy({(32...126).contains($0)}) else{return nil}
            return String(bytes:head,encoding:.ascii)
        }
        var state=PluginState(presetName:(values["name"] as? String).map{String($0.prefix(200))},
                              componentType:number("type").flatMap(fourCC),
                              componentSubtype:number("subtype").flatMap(fourCC),
                              manufacturer:number("manufacturer").flatMap(fourCC),
                              version:number("version"),stateBytes:vendor?.count ?? 0,
                              stateMagic:magic,programCount:nil)
        if let vendor,magic=="VC2!",vendor.count<=4_000_000 {
            // Count the vendor bank's own records without decoding them. The delimiter
            // check keeps a <programs> wrapper from being counted as a program.
            let payload=vendor.dropFirst(min(9,vendor.count)),needle=Data("<program".utf8)
            var programs=0,offset=payload.startIndex
            while programs<4096,let range=payload.range(of:needle,in:offset..<payload.endIndex) {
                let after=range.upperBound
                let delimiter=after<payload.endIndex ? payload[after] : UInt8(ascii:">")
                if delimiter==UInt8(ascii:" ") || delimiter==UInt8(ascii:">") || delimiter==UInt8(ascii:"/") {programs+=1}
                offset=after
            }
            state.programCount=programs
        }
        return state
    }
    static func inspect(_ patch:URL)throws->Report {
        guard patch.pathExtension.lowercased()=="patch",(try patch.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])).isDirectory==true,
              (try patch.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink != true else{throw Failure.invalid("Choose a MainStage .patch folder.")}
        let bytes=try read(patch.appendingPathComponent("data.plist"),in:patch)
        guard let document=try PropertyListSerialization.propertyList(from:bytes,options:[],format:nil) as? [String:Any],
              let channels=document["channels"] as? [[String:Any]],!channels.isEmpty,channels.count<=128 else{throw Failure.invalid("This patch does not contain a supported channel list.")}
        let patchData=document["patch"] as? [String:Any]
        let engine=patchData?["engineNode"] as? [String:Any]
        let authoredName=engine?["name"] as? String ?? patch.deletingPathExtension().lastPathComponent
        guard authoredName.count<=200 else{throw Failure.invalid("The patch name exceeds the supported length.")}
        var result=Report(name:authoredName,channels:[],blockers:[],preservedFiles:["data.plist":digest(bytes)])
        if document["StageKeys.channelStripOnly"] as? Bool==true {result.blockers.append("Imported channel strip only: parent-patch buses, sends and patch-level MIDI settings were not included in the CST document.")}
        for channel in channels {
            guard let filename=channel["Filename"] as? String,filename==URL(fileURLWithPath:filename).lastPathComponent,filename.lowercased().hasSuffix(".cst") else{throw Failure.invalid("Unsafe or unsupported channel-strip reference.")}
            let data=try read(patch.appendingPathComponent(filename),in:patch)
            let name=channel["Channel_name"] as? String ?? filename
            guard name.count<=200 else{throw Failure.invalid("A channel name exceeds the supported length.")}
            var deviceList:[Device]=[]
            do{deviceList=try devices(data)}catch{result.blockers.append("\(name): \(error.localizedDescription)")}
            let instruments=instrumentReferences(data)
            let mappings=data.range(of:Data("MAPlugInParameterMapping".utf8)) != nil || data.range(of:Data("MABaseplateParameterMapping".utf8)) != nil
            let midi=channel["MIDITransform"] != nil
            result.channels.append(Channel(name:name,file:filename,sha256:digest(data),instruments:instruments,devices:deviceList,hasMappings:mappings,hasMIDIState:midi))
            if let family=result.channels.last?.unsupportedInstrumentFamily {
                result.blockers.append("\(name): \(family) has no native StageKeys engine; no substitute instrument will be created.")
            }
            let audioUnits=result.channels.last?.thirdPartyAudioUnits ?? []
            if !audioUnits.isEmpty {
                let described=audioUnits.prefix(4).map{unit in
                    unit.name+(unit.audioUnitIdentity.map{" (\($0))"} ?? "")
                }.joined(separator:", ")
                let retained=audioUnits.compactMap{$0.pluginState?.summary}.first.map{" Saved state: \($0)."} ?? ""
                result.blockers.append("\(name): third-party Audio Unit \(described) is not translated; install the same Audio Unit version or retain the source."+retained)
            }
            result.preservedFiles[filename]=digest(data)
            // Retention is lossless; playback translation must be proven separately.
            // Merely finding an EXS filename is not a complete patch conversion.
            result.blockers.append("\(name): proprietary channel-strip parameter/routing translation is not yet verified.")
            if instruments.isEmpty,channel["Channel_inputIsBus"] as? Bool != true {result.blockers.append("\(name): no portable EXS sampler reference was found.")}
            if mappings {result.blockers.append("\(name): Smart Control macro mappings require translation.")}
        }
        return result
    }
    /// Archive all source files byte-for-byte. Paths, hashes, mappings, effects,
    /// MIDI state and unknown records survive, but no incomplete sound is added.
    static func retain(_ patch:URL,to destination:URL)throws->Report {
        if patch.pathExtension.lowercased()=="cst" {
            // A channel strip is a document, not a full patch. Build an explicit
            // metadata wrapper while preserving the actual CST bytes verbatim.
            let bytes=try read(patch,in:patch.deletingLastPathComponent())
            _ = try devices(bytes)
            let staging=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".patch",isDirectory:true)
            try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:true)
            defer{try? FileManager.default.removeItem(at:staging)}
            let name=patch.deletingPathExtension().lastPathComponent
            let document:[String:Any]=["StageKeys.channelStripOnly":true,"patch":["engineNode":["name":name]],"channels":[["Filename":patch.lastPathComponent,"Channel_name":name]]]
            try bytes.write(to:staging.appendingPathComponent(patch.lastPathComponent),options:.atomic)
            try PropertyListSerialization.data(fromPropertyList:document,format:.binary,options:0).write(to:staging.appendingPathComponent("data.plist"),options:.atomic)
            return try retain(staging,to:destination)
        }
        let report=try inspect(patch)
        let manager=FileManager.default
        let root=patch.resolvingSymlinksInPath().standardizedFileURL
        guard !manager.fileExists(atPath:destination.path) else{throw Failure.invalid("The conversion archive already exists.")}
        try manager.createDirectory(at:destination,withIntermediateDirectories:true)
        do {
            let source=destination.appendingPathComponent("Source.patch",isDirectory:true)
            try manager.createDirectory(at:source,withIntermediateDirectories:false)
            guard let enumeration=manager.enumerator(at:root,includingPropertiesForKeys:[.isSymbolicLinkKey,.isDirectoryKey,.isRegularFileKey,.fileSizeKey]) else{throw Failure.invalid("Could not read patch files.")}
            var count=0,total=0,audioTotal=0
            for case let file as URL in enumeration {
                count+=1;guard count<=4096,contained(file,in:root) else{throw Failure.invalid("Patch file limit or unsafe reference.")}
                let values=try file.resourceValues(forKeys:[.isSymbolicLinkKey,.isDirectoryKey,.isRegularFileKey,.fileSizeKey])
                guard values.isSymbolicLink != true else{throw Failure.invalid("Symbolic links cannot be archived as patch assets.")}
                let relative=String(file.resolvingSymlinksInPath().standardizedFileURL.path.dropFirst(root.path.count+1)),target=source.appendingPathComponent(relative)
                if values.isDirectory==true {try manager.createDirectory(at:target,withIntermediateDirectories:true)}
                else {
                    try manager.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                    if ["caf","wav","aif","aiff","flac"].contains(file.pathExtension.lowercased()) {
                        let size=values.fileSize ?? Int.max
                        guard values.isRegularFile==true,size>=0,size<=2_000_000_000,audioTotal<=4_000_000_000-size else{throw Failure.invalid("Bundled sample archive exceeds its 4 GB total / 2 GB file limit.")}
                        audioTotal+=size
                        // Audio assets can be much larger than serialized documents.
                        // Copy and hash streams; never load a whole piano into Data.
                        let before=try AssetDigest.sha256(file)
                        try manager.copyItem(at:file,to:target)
                        guard try AssetDigest.sha256(target)==before,try AssetDigest.sha256(file)==before else{throw Failure.invalid("A bundled sample changed during source retention. Retry the import.")}
                    } else {
                        let data=try read(file,in:root);total+=data.count
                        guard total<=128_000_000 else{throw Failure.invalid("Patch document archive exceeds 128 MB.")}
                        try data.write(to:target,options:.atomic)
                        guard try Data(contentsOf:target)==data else{throw Failure.invalid("Patch archive verification failed.")}
                    }
                }
            }
            for (name,hash) in report.preservedFiles {guard digest(try read(source.appendingPathComponent(name),in:source))==hash else{throw Failure.invalid("Source changed while archiving. Retry the import.")}}
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(report).write(to:destination.appendingPathComponent("conversion-report.json"),options:.atomic)
            return report
        }catch{try? manager.removeItem(at:destination);throw error}
    }
}

/// Matches the Audio Unit state a MainStage channel saved against the components
/// installed on this machine. Matching is identity-only: no plug-in is loaded here,
/// and the saved subtype is reported so a version swap is never silent.
enum MainStageAudioUnit {
    struct Match:Equatable {
        var identity:ExternalAUIdentity
        /// Class info in the form `ExternalInstruments` persists and restores.
        var state:Data
        /// False when the installed component has a different subtype than the save.
        var exactSubtype:Bool
        var savedIdentity:String
        var savedVersion:Int?
        var installedVersion:String? {identity.version}
    }
    /// Build the state an installed component would receive. The wrapper is the class
    /// info document MainStage stored, so it is passed through byte-identically.
    static func state(for device:MainStagePatch.Device,in data:Data)->Data? {
        guard device.format=="PSDD" else{return nil}
        let end=min(data.count,device.offset+device.byteCount)
        guard end>device.offset else{return nil}
        return MainStagePatch.pluginStateData(in:data.subdata(in:device.offset..<end))
    }
    /// Prefer an exact component triple; otherwise accept the same type, manufacturer
    /// and display name only when there is a single candidate. A name is not a unique component identity.
    static func match(_ device:MainStagePatch.Device,state:Data,installed:[ExternalAUIdentity])->Match? {
        guard device.format=="PSDD",let saved=device.pluginState,
              let type=saved.componentType.flatMap(code),
              let manufacturer=saved.manufacturer.flatMap(code) else{return nil}
        let subtype=saved.componentSubtype.flatMap(code)
        let family=installed.filter { $0.type==type && $0.manufacturer==manufacturer }
        let identity:ExternalAUIdentity
        if let exact=family.first(where:{$0.subtype==subtype}) {
            // Component identity survives display-name changes between releases.
            identity=exact
        } else {
            let candidates=family.filter{$0.name.caseInsensitiveCompare(device.name) == .orderedSame}
            // Enumeration order is not evidence of a compatible replacement.
            guard candidates.count==1,let only=candidates.first else{return nil}
            identity=only
        }
        let exact=identity.subtype==subtype && identity.type==type && identity.manufacturer==manufacturer
        // The host applies class info only when its component identity matches the
        // installed component, so a version-changed match rewrites those three keys.
        // The vendor payload is preserved byte-for-byte.
        guard let restorable=exact ? state : rewritten(state,identity:identity) else{return nil}
        return Match(identity:identity,state:restorable,exactSubtype:identity.subtype==subtype,
                     savedIdentity:saved.identity ?? device.name,savedVersion:saved.version)
    }
    /// A channel turned into a playable layer. Nothing is loaded or rendered here: the
    /// layer carries the installed component and the class info the rack restores.
    struct Hosted:Equatable {
        var layer:Layer
        var identity:ExternalAUIdentity
        var exactSubtype:Bool
        var notes:[String]
    }
    /// Build the layer that hosts a saved Audio Unit. A plug-in that is not installed,
    /// is unavailable, or whose state cannot be read stays an explicit failure rather
    /// than becoming a silent substitute sound.
    static func hostedLayer(name:String,device:MainStagePatch.Device,state:Data,
                            installed:[ExternalAUIdentity])throws->Hosted {
        guard let match=match(device,state:state,installed:installed) else {
            let identity=device.audioUnitIdentity.map{" (\($0))"} ?? ""
            throw MainStagePatch.Failure.invalid("the saved Audio Unit \(device.name)\(identity) is not installed or cannot be matched unambiguously; install that exact component to host this channel, or retain the source.")
        }
        if let reason=match.identity.unavailableReason {
            throw MainStagePatch.Failure.invalid("\(match.identity.displayName) is installed but unavailable. \(reason)")
        }
        var layer=Layer(name:name,instrument:-1,gain:1)
        layer.external=ExternalSound(kind:.audioUnit,name:device.name,component:match.identity)
        layer.pluginState=match.state
        var notes:[String]=[]
        if let saved=device.pluginState {
            notes.append("hosted \(device.name); restored \(saved.summary).")
        }
        if !match.exactSubtype {
            let installedVersion=match.installedVersion.map{" (\($0))"} ?? ""
            notes.append("the saved component \(match.savedIdentity) differs from the installed \(identityText(match.identity))\(installedVersion); parameters were applied by the plug-in, and values whose meaning changed between versions fall back to its defaults. Verify the sound before performing.")
        }
        return Hosted(layer:layer,identity:match.identity,exactSubtype:match.exactSubtype,notes:notes)
    }
    private static func rewritten(_ state:Data,identity:ExternalAUIdentity)->Data? {
        guard var values=try? PropertyListSerialization.propertyList(from:state,options:[],format:nil) as? [String:Any] else{return nil}
        values["type"]=NSNumber(value:identity.type)
        values["subtype"]=NSNumber(value:identity.subtype)
        values["manufacturer"]=NSNumber(value:identity.manufacturer)
        guard let output=try? PropertyListSerialization.data(fromPropertyList:values,format:.binary,options:0),
              output.count<=2_000_000 else{return nil}
        return output
    }
    /// Readable component identity, so a version change names components the way the
    /// channel strip recorded them instead of printing three decimal numbers.
    static func identityText(_ identity:ExternalAUIdentity)->String {
        [text(identity.type),text(identity.subtype),text(identity.manufacturer)].compactMap{$0}.joined(separator:"/")
    }
    private static func text(_ value:UInt32)->String? {
        let bytes=(0..<4).map{UInt8((value >> (24-$0*8)) & 255)}
        guard bytes.allSatisfy({(32...126).contains($0)}) else{return nil}
        return String(bytes:bytes,encoding:.ascii)
    }
    /// Four-character component codes are stored as their big-endian text value.
    private static func code(_ text:String)->UInt32? {
        let bytes=Array(text.utf8)
        guard bytes.count==4 else{return nil}
        return bytes.reduce(UInt32(0)){($0 << 8) | UInt32($1)}
    }
}
