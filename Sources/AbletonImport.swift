import Foundation
import AVFoundation
import zlib

enum AbletonImportError:LocalizedError {
    case invalid(String)
    var errorDescription:String? {if case .invalid(let detail)=self{return "Ableton import: " + detail};return nil}
}
/// Parses saved sample maps only. Never executes Live devices or preset content.
enum AbletonImport {
    final class Node {
        let name:String
        let value:String?
        var children:[Node]=[]
        weak var parent:Node?
        init(_ name:String,_ value:String?){self.name=name;self.value=value}
        func at(_ path:String)->Node? {path.split(separator:"/").reduce(Optional(self)) {node,key in node?.children.first{$0.name == key}}}
        func string(_ path:String,_ fallback:String="")->String {at(path)?.value ?? fallback}
        func number(_ path:String,_ fallback:Double=0)throws->Double {
            guard let raw=at(path)?.value else{return fallback}
            guard let value=Double(raw),value.isFinite,abs(value)<=1_000_000_000_000 else{throw AbletonImportError.invalid("Invalid numeric value at \(path).")};return value
        }
        func flag(_ path:String,_ fallback:Bool=false)->Bool {guard let s=at(path)?.value else{return fallback};return s == "true" || s == "1"}
        func all(_ tag:String)->[Node] {(name == tag ? [self] : []) + children.flatMap{$0.all(tag)}}
    }
    final class Parser:NSObject,XMLParserDelegate {
        var root:Node?
        var stack:[Node]=[]
        var count=0
        var rejected=false
        func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]){
            count+=1
            guard count<=300_000,stack.count<128 else{rejected=true;parser.abortParsing();return}
            let n=Node(name,attributes["Value"]);n.parent=stack.last
            if let parent=stack.last {parent.children.append(n)} else{root=n};stack.append(n)
        }
        func parser(_ parser:XMLParser,didEndElement:String,namespaceURI:String?,qualifiedName:String?){if !stack.isEmpty{stack.removeLast()}}
    }
    struct Conversion {
        var preset:URL
        var name:String
        var zones:Int
        var layers:Int
        var warnings:[String]
        var sampleHashes:[String:String]
        var rack:ImportedRack
        var midi:MIDIProgram?
    }
    static func readXML(_ url:URL)throws->Node {
        let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max
        guard size<=32*1024*1024 else{throw AbletonImportError.invalid("Preset exceeds size limit.")}
        let compressed=try Data(contentsOf:url)
        let bytes:Data
        if compressed.starts(with:[0x1f,0x8b]) {
            guard let gz=gzopen(url.path,"rb") else{throw AbletonImportError.invalid("Cannot read compressed preset.")}
            defer{gzclose(gz)}
            var decoded=Data(),buffer=[UInt8](repeating:0,count:65536)
            while true {
                let count=gzread(gz,&buffer,UInt32(buffer.count))
                guard count>=0 else{throw AbletonImportError.invalid("Corrupt gzip preset.")}
                if count==0{break}
                guard decoded.count+Int(count)<=32*1024*1024 else{throw AbletonImportError.invalid("Expanded preset exceeds size limit.")}
                decoded.append(contentsOf:buffer.prefix(Int(count)))
            };bytes=decoded
        } else{bytes=compressed}
        let upper=String(decoding:bytes,as:UTF8.self).uppercased()
        guard !upper.contains("<!DOCTYPE"),!upper.contains("<!ENTITY") else{throw AbletonImportError.invalid("XML entities are not supported.")}
        let delegate=Parser(),parser=XMLParser(data:bytes);parser.delegate=delegate;parser.shouldResolveExternalEntities=false
        guard parser.parse(),!delegate.rejected,let root=delegate.root,root.name == "Ableton" else{throw AbletonImportError.invalid("Malformed or unsupported preset XML.")}
        return root
    }
    static func sampleURL(_ ref:Node,root:URL)throws->URL {
        let name=ref.string("Name")
        guard !name.isEmpty,name.count<=256,!name.contains("/"),!name.contains("\\"),!name.contains("\0"),name != ".",name != ".." else{throw AbletonImportError.invalid("Unsafe sample name.")}
        let resolvedRoot=root.resolvingSymlinksInPath().standardizedFileURL
        // Extracted packs flatten original audio under Samples; installed Live projects use Samples/Imported.
        for folder in ["","Samples","Samples/Imported","Imported"] {
            for leaf in [name,name+".flac"] {
                let candidate=root.appendingPathComponent(folder).appendingPathComponent(leaf).resolvingSymlinksInPath().standardizedFileURL
                guard candidate.path.hasPrefix(resolvedRoot.path+"/") else{continue}
                if (try? candidate.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true,
                   ["aif","aiff","wav","caf","flac"].contains(candidate.pathExtension.lowercased()){return candidate}
            }
        }
        throw AbletonImportError.invalid("Missing sample: \(name). Choose its sample folder.")
    }
    static func convert(_ source:URL,sampleRoot:URL,to output:URL)throws->Conversion {
        precondition(Thread.isMainThread)
        let access=source.startAccessingSecurityScopedResource(),sampleAccess=sampleRoot.startAccessingSecurityScopedResource()
        defer{if access{source.stopAccessingSecurityScopedResource()};if sampleAccess{sampleRoot.stopAccessingSecurityScopedResource()}}
        let root=try readXML(source)
        let devices=root.all("OriginalSimpler")+root.all("MultiSampler")
        guard !devices.isEmpty,devices.count<=64 else{throw AbletonImportError.invalid("No supported Simpler/Sampler sample map.")}
        var warnings=Set<String>()
        var nativeLayers:[ObjectIdentifier:Int]=[:]
        let firstPart=devices.flatMap{$0.all("MultiSamplePart")}.first
        guard let firstRef=firstPart?.at("SampleRef/FileRef") else{throw AbletonImportError.invalid("Sample map is empty.")}
        let first=try sampleURL(firstRef,root:sampleRoot)
        let templateSampler=AVAudioUnitSampler();try templateSampler.loadAudioFiles(at:[first])
        guard var state=templateSampler.auAudioUnit.fullState,var instrument=state["Instrument"] as? [String:Any],let template=(instrument["Layers"] as? [[String:Any]])?.first else{throw AbletonImportError.invalid("Cannot initialize the native sampler.")}
        var layers:[[String:Any]]=[],refs:[String:String]=[:],total=0,hashes:[String:String]=[:],waveformIDs:[URL:Int]=[:]
        for device in devices {
            if !device.flag("On/Manual",true){continue}
            var ancestors:[Node]=[];var ancestor=device.parent
            while let node=ancestor{ancestors.append(node);ancestor=node.parent}
            let branches=ancestors.filter{$0.name == "InstrumentBranchPreset"}
            var minKey=0,maxKey=127,minVel=1,maxVel=127,branchGain=1.0,skip=false
            for branch in branches {
                minKey=max(minKey,Int(try branch.number("ZoneSettings/KeyRange/Min",0)));maxKey=min(maxKey,Int(try branch.number("ZoneSettings/KeyRange/Max",127)))
                minVel=max(minVel,Int(try branch.number("ZoneSettings/VelocityRange/Min",1)));maxVel=min(maxVel,Int(try branch.number("ZoneSettings/VelocityRange/Max",127)))
                if let mixer=branch.at("MixerPreset/AbletonDevicePreset/Device/AudioBranchMixerDevice") {
                    if !mixer.flag("Speaker/Manual",true){skip=true}
                    branchGain *= try mixer.number("Volume/Manual",1)
                }
                if let group=branch.parent?.parent,group.name == "GroupDevicePreset",let groupDevice=group.at("Device/InstrumentGroupDevice") {
                    let selector=try groupDevice.number("ChainSelector/Manual",0)
                    let selectorMin=try branch.number("BranchSelectorRange/Min",0),selectorMax=try branch.number("BranchSelectorRange/Max",127)
                    let fadeMin=try branch.number("BranchSelectorRange/CrossfadeMin",selectorMin),fadeMax=try branch.number("BranchSelectorRange/CrossfadeMax",selectorMax)
                    if selector < selectorMin || selector > selectorMax{skip=true}
                    else if selector < fadeMin,fadeMin>selectorMin {branchGain *= max(0,(selector-selectorMin)/(fadeMin-selectorMin));warnings.insert("Saved rack-selector crossfade weights are translated as static linear gain.")}
                    else if selector > fadeMax,selectorMax>fadeMax {branchGain *= max(0,(selectorMax-selector)/(selectorMax-fadeMax));warnings.insert("Saved rack-selector crossfade weights are translated as static linear gain.")}
                    if !groupDevice.flag("On/Manual",true){skip=true}
                    let siblings=branch.parent?.children.filter{["InstrumentBranchPreset","AudioEffectBranchPreset","MidiEffectBranchPreset"].contains($0.name)} ?? []
                    if siblings.contains(where:{$0.flag("IsSoloed")}) && !branch.flag("IsSoloed"){skip=true}
                }
            }
            if skip || branchGain<=0 || minKey>maxKey || minVel>maxVel{continue}
            if device.flag("Player/Reverse/Manual"){throw AbletonImportError.invalid("Reverse playback requires a separate translation.")}
            if (try device.number("SimplerSlicing/PlaybackMode",0)) != 0 {throw AbletonImportError.invalid("Sliced/one-shot Simpler playback is not supported yet.")}
            if device.flag("Player/SubOsc/IsOn/Manual"){warnings.insert("Sampler sub-oscillator is not translated.")}
            warnings.insert("Filter/LFO modulation, velocity response, envelope curves, zone crossfades and release loops may differ from Live.")
            let transpose=try device.number("Pitch/TransposeKey/Manual",0),fine=try device.number("Pitch/TransposeFine/Manual",0)
            let volume=try device.number("VolumeAndPan/Volume/Manual",0)
            guard abs(transpose)<=96,abs(fine)<=1200,volume>=(-96),volume<=36,branchGain>=0,branchGain<=16 else{throw AbletonImportError.invalid("Unsupported tuning or level.")}
            var zones:[[String:Any]]=[]
            for part in device.all("MultiSamplePart") where part.flag("IsActive",true) {
                let lo=max(minKey,Int(try part.number("KeyRange/Min",0))),hi=min(maxKey,Int(try part.number("KeyRange/Max",127)))
                let vl=max(minVel,Int(try part.number("VelocityRange/Min",1))),vh=min(maxVel,Int(try part.number("VelocityRange/Max",127)))
                let selector=try device.number("Player/SampleSelector/Manual",0)
                let selectorMin=try part.number("SelectorRange/Min",0),selectorMax=try part.number("SelectorRange/Max",127)
                if lo>hi || vl>vh || selector < selectorMin || selector > selectorMax{continue}
                guard lo>=0,hi<=127,vl>=1,vh<=127,let ref=part.at("SampleRef/FileRef") else{throw AbletonImportError.invalid("Invalid key/velocity range.")}
                let url=try sampleURL(ref,root:sampleRoot),audio=try AVAudioFile(forReading:url)
                let start=Int(try part.number("SampleStart",0)),end=Int(try part.number("SampleEnd",Double(audio.length-1)))
                let rootKey=Int(try part.number("RootKey",60))-Int(transpose)
                guard start>=0,end>=start,end<Int(audio.length),(0...127).contains(rootKey) else{throw AbletonImportError.invalid("Invalid sample bounds or root key.")}
                let id=waveformIDs[url] ?? (268435456+waveformIDs.count)
                waveformIDs[url]=id;total+=1
                guard total<=4096 else{throw AbletonImportError.invalid("Too many sample zones.")}
                let partVolume=try part.number("Volume",1)
                guard partVolume>0,partVolume<=16 else{throw AbletonImportError.invalid("Unsupported zone level.")}
                var zone:[String:Any]=["ID":zones.count,"enabled":true,"name":part.string("Name",url.lastPathComponent),"waveform":id,"min key":lo,"max key":hi,"min vel":vl,"max vel":vh,"root key":rootKey,"sample start":start,"sample end":end,"gain":20*log10(partVolume*max(branchGain,0.00001))+volume,"fine tune":fine+(try part.number("Detune",0)),"pan":try part.number("Panorama",0)]
                let mode=Int(try part.number("SustainLoop/Mode",3))
                zone["loop enabled"]=mode == 1 || mode == 2
                if mode == 1 || mode == 2 {
                    let loopStart=Int(try part.number("SustainLoop/Start",0)),loopEnd=Int(try part.number("SustainLoop/End",Double(end)))
                    guard loopStart>=start,loopEnd>loopStart,loopEnd<=end else{throw AbletonImportError.invalid("Invalid sustain loop.")}
                    zone["loop start"]=loopStart;zone["loop end"]=loopEnd
                    if mode == 2{warnings.insert("Bidirectional loops currently use forward playback.")}
                    if (try part.number("SustainLoop/Crossfade",0))>0{warnings.insert("Live loop crossfade is not translated; loop positions are preserved.")}
                }
                zones.append(zone);refs["Sample:\(id)"]=url.path
                if hashes[url.lastPathComponent] == nil{hashes[url.lastPathComponent]=try AbletonArchive.sha256(url)}
            }
            if zones.isEmpty{continue}
            var layer=template;layer["ID"]=layers.count;layer["name"]=device.string("UserName","Imported Layer");layer["Zones"]=zones;layer["Filters"]=["ID":0,"enabled":false,"cutoff":20000.0,"resonance":0.0]
            var envelopes=template["Envelopes"] as? [[String:Any]] ?? []
            if !envelopes.isEmpty,var stages=envelopes[0]["Stages"] as? [[String:Any]] {
                let attack=try device.number("VolumeAndPan/Envelope/AttackTime/Manual",0)/1000
                let decay=try device.number("VolumeAndPan/Envelope/DecayTime/Manual",1000)/1000
                let sustain=try device.number("VolumeAndPan/Envelope/SustainLevel/Manual",1)
                let release=try device.number("VolumeAndPan/Envelope/ReleaseTime/Manual",100)/1000
                guard attack>=0,attack<=120,decay>=0,decay<=120,sustain>=0,sustain<=1,release>=0,release<=120 else{throw AbletonImportError.invalid("Invalid amplitude envelope.")}
                for i in stages.indices {
                    switch stages[i]["stage"] as? Int {case 1:stages[i]["time"]=attack;case 3:stages[i]["time"]=decay;case 4:stages[i]["level"]=sustain;case 5:stages[i]["time"]=release;default:break}
                };envelopes[0]["Stages"]=stages;layer["Envelopes"]=envelopes
            }
            // Native sampler connection IDs encode the owning layer in bits 8–15.
            // Cloning layer zero without rebasing these leaves higher layers silent.
            if var connections=layer["Connections"] as? [[String:Any]] {
                for index in connections.indices {
                    for key in ["source","destination","control"] {
                        if let value=connections[index][key] as? Int,value>=0x10000000 {connections[index][key]=value+layers.count*256}
                    }
                }
                layer["Connections"]=connections
            }
            nativeLayers[ObjectIdentifier(device)]=layers.count
            layers.append(layer)
        }
        guard !layers.isEmpty else{throw AbletonImportError.invalid("No active sample layers at the saved rack selection.")}
        let translated=try behavior(root,layerMapping:nativeLayers)
        guard translated.rack.validate() else{throw AbletonImportError.invalid("Translated processing graph exceeds limits or has invalid settings.")}
        warnings.formUnion(translated.warnings)
        let name=source.deletingPathExtension().lastPathComponent
        instrument["Layers"]=layers;instrument["name"]=name;instrument["voice count"]=64
        state["Instrument"]=instrument;state["file-references"]=refs;state["name"]=name;state["gain"]=0;state["voice count"]=64
        try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:output,options:.atomic)
        return Conversion(preset:output,name:name,zones:total,layers:layers.count,warnings:warnings.sorted(),sampleHashes:hashes,rack:translated.rack,midi:translated.midi)
    }
    /// Isolate each layer so an audible neighboring layer cannot hide a silent conversion.
    static func validatePlayback(_ preset:URL)throws->Int {
        guard let state=try PropertyListSerialization.propertyList(from:Data(contentsOf:preset),options:[],format:nil) as? [String:Any],
              let instrument=state["Instrument"] as? [String:Any],let layers=instrument["Layers"] as? [[String:Any]],!layers.isEmpty else{throw AbletonImportError.invalid("Invalid native preset.")}
        if layers.count==1{return try validateSingleLayer(preset)}
        var checks=0
        for original in layers {
            var layer=original
            let oldID=layer["ID"] as? Int ?? 0;layer["ID"]=0
            if var connections=layer["Connections"] as? [[String:Any]] {
                for i in connections.indices {for key in ["source","destination","control"] {if let value=connections[i][key] as? Int,value>=0x10000000{connections[i][key]=value-oldID*256}}}
                layer["Connections"]=connections
            }
            var isolated=state,isolatedInstrument=instrument;isolatedInstrument["Layers"]=[layer];isolated["Instrument"]=isolatedInstrument
            let temporary=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".aupreset")
            defer{try? FileManager.default.removeItem(at:temporary)}
            try PropertyListSerialization.data(fromPropertyList:isolated,format:.xml,options:0).write(to:temporary)
            checks += try validateSingleLayer(temporary)
        }
        return checks
    }
    /// Check every distinct mapped root at an in-range velocity using Apple's sampler.
    private static func validateSingleLayer(_ preset:URL)throws->Int {
        let state=try PropertyListSerialization.propertyList(from:Data(contentsOf:preset),options:[],format:nil) as? [String:Any]
        let instrument=state?["Instrument"] as? [String:Any]
        let zones=(instrument?["Layers"] as? [[String:Any]] ?? []).flatMap{$0["Zones"] as? [[String:Any]] ?? []}
        guard !zones.isEmpty else{throw AbletonImportError.invalid("Empty native sample map.")}
        let engine=AVAudioEngine(),sampler=AVAudioUnitSampler()
        engine.attach(sampler);engine.connect(sampler,to:engine.mainMixerNode,format:nil)
        let format=AVAudioFormat(standardFormatWithSampleRate:44100,channels:2)!
        try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:512)
        try sampler.loadInstrument(at:preset);try engine.start();defer{engine.stop()}
        let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:512)!
        var tested:Set<String>=[]
        for zone in zones {
            let lo=zone["min key"] as? Int ?? 0,hi=zone["max key"] as? Int ?? 127,vl=zone["min vel"] as? Int ?? 1,vh=zone["max vel"] as? Int ?? 127
            let note=max(lo,min(hi,zone["root key"] as? Int ?? 60)),velocity=max(vl,min(vh,100)),key="\(note):\(velocity)"
            if tested.contains(key){continue};tested.insert(key)
            sampler.sendController(120,withValue:0,onChannel:0);sampler.startNote(UInt8(note),withVelocity:UInt8(velocity),onChannel:0)
            var peak:Float=0
            for _ in 0..<173 {
                guard try engine.renderOffline(512,to:buffer) == .success else{throw AbletonImportError.invalid("Offline render failed.")}
                for c in 0..<2{for i in 0..<Int(buffer.frameLength){let v=buffer.floatChannelData![c][i];guard v.isFinite else{throw AbletonImportError.invalid("Nonfinite sample output.")};peak=max(peak,abs(v))}}
            }
            sampler.stopNote(UInt8(note),onChannel:0)
            guard peak>0.00001 else{throw AbletonImportError.invalid("Silent mapped note \(key).")}
        }
        return tested.count
    }

}

extension AbletonImport {
    struct Behavior {
        var rack = ImportedRack(translationVersion:4)
        var midi: MIDIProgram?
        var macroSources:[Int:ObjectIdentifier]=[:]
        var warnings: [String] = []
    }
    /// Preserve serial order and split instrument voices separately from shared-input audio racks.
    static func behavior(_ root:Node,layerMapping:[ObjectIdentifier:Int]?=nil,entry:Node?=nil,depth:Int=0)throws->Behavior {
        guard depth<12 else{throw AbletonImportError.invalid("Parallel rack depth exceeds limit.")}
        var result=Behavior()
        typealias ScopedDevice=(device:Node,owner:Node?)
        var owners:[Node]=[]
        var handled=Set<ObjectIdentifier>()
        var promoted:[(owner:Node,macro:ImportedMacro,path:[Int])]=[]
        var audioPromoted:[(owner:Node,macro:ImportedMacro,path:[Int])]=[]
        var audioPlans:[ObjectIdentifier:(owner:Node?,name:String,branches:[ImportedAudioBranch],ownedMacros:[[Int]])]=[:]
        func expand(_ preset:Node,_ inherited:Node?,_ depth:Int)throws->[ScopedDevice] {
            guard depth<16 else{throw AbletonImportError.invalid("Nested rack depth exceeds limit.")}
            if preset.name.hasSuffix("BranchPreset") {
                let owner=preset.parent?.parent?.at("Device")?.children.first
                if let owner {owners.append(owner)}
                var devices=try (preset.at("DevicePresets")?.children ?? []).flatMap{try expand($0,owner,depth+1)}
                if preset.name == "AudioEffectBranchPreset",let mixer=preset.at("MixerPreset/AbletonDevicePreset/Device/AudioBranchMixerDevice") {devices.append((mixer,owner))}
                return devices
            }
            guard preset.name == "GroupDevicePreset" else {
                return preset.at("Device")?.children.map{($0,inherited)} ?? []
            }
            let owner=preset.at("Device")?.children.first
            if let owner,!owner.flag("On/Manual",true){return []}
            if let owner {owners.append(owner)}
            let branches=preset.at("BranchPresets")?.children.filter{["InstrumentBranchPreset","AudioEffectBranchPreset","MidiEffectBranchPreset"].contains($0.name)} ?? []
            guard branches.count==1 else {
                if owner?.name == "AudioEffectGroupDevice",!branches.isEmpty,branches.count<=16 {
                    var plans:[ImportedAudioBranch]=[],ownedMacros:[[Int]]=[]
                    for (index,branch) in branches.enumerated() {
                        let translated=try behavior(root,layerMapping:layerMapping,entry:branch,depth:depth+1)
                        guard translated.midi == nil,translated.rack.branches == nil else{throw AbletonImportError.invalid("Audio rack contains instrument or MIDI processing.")}
                        ownedMacros.append(translated.rack.macros.filter{translated.macroSources[$0.index] == owner.map(ObjectIdentifier.init)}.map(\.index))
                        let mixer=branch.at("MixerPreset/AbletonDevicePreset/Device/AudioBranchMixerDevice")
                        let soloed=branches.contains{$0.flag("IsSoloed")}
                        let selector=try owner?.number("ChainSelector/Manual",0) ?? 0
                        let minimum=try branch.number("BranchSelectorRange/Min",0),maximum=try branch.number("BranchSelectorRange/Max",127)
                        let active=(mixer?.flag("Speaker/Manual",true) ?? true) && (!soloed || branch.flag("IsSoloed")) && selector>=minimum && selector<=maximum
                        let pan=Float(max(-1,min(1,try mixer?.number("Pan/Manual",0) ?? 0)))
                        plans.append(ImportedAudioBranch(name:branch.string("Name","Audio Branch \(index+1)"),rack:translated.rack,pan:pan,enabled:active))
                        result.warnings += translated.warnings.map{"Audio Branch \(index+1): \($0)"}
                    }
                    let marker=Node("StageKeysAudioRack",nil)
                    audioPlans[ObjectIdentifier(marker)]=(owner,preset.string("Name","Parallel Audio Rack"),plans,ownedMacros)
                    for device in preset.all("Device").flatMap(\.children) {handled.insert(ObjectIdentifier(device))}
                    return [(marker,owner)]
                }
                guard owner?.name == "InstrumentGroupDevice",let layerMapping,result.rack.branches == nil else {
                    result.warnings.append("This parallel rack cannot be routed as an instrument split; its branch-specific processing remains unsupported.")
                    return []
                }
                var planned:[ImportedBranch]=[]
                for (index,branch) in branches.enumerated() {
                    let layers=Set((branch.all("OriginalSimpler")+branch.all("MultiSampler")).compactMap{layerMapping[ObjectIdentifier($0)]}).sorted()
                    guard !layers.isEmpty else{continue}
                    let translated=try behavior(root,layerMapping:layerMapping,entry:branch,depth:depth+1)
                    if let owner {
                        for macro in translated.rack.macros where translated.macroSources[macro.index] == ObjectIdentifier(owner) {promoted.append((owner,macro,[planned.count]))}
                    }
                    var plan=ImportedBranch(name:branch.string("Name","Branch \(index+1)"),sampleLayers:layers,rack:translated.rack,midi:translated.midi)
                    if let owner {plan.rack.macros.removeAll{translated.macroSources[$0.index] == ObjectIdentifier(owner)}}
                    plan.low=max(0,min(127,Int(try branch.number("ZoneSettings/KeyRange/Min",0))))
                    plan.high=max(plan.low,min(127,Int(try branch.number("ZoneSettings/KeyRange/Max",127))))
                    plan.velocityLow=max(1,min(127,Int(try branch.number("ZoneSettings/VelocityRange/Min",1))))
                    plan.velocityHigh=max(plan.velocityLow,min(127,Int(try branch.number("ZoneSettings/VelocityRange/Max",127))))
                    if let mixer=branch.at("MixerPreset/AbletonDevicePreset/Device/AudioBranchMixerDevice") {plan.pan=Float(max(-1,min(1,try mixer.number("Pan/Manual",0))))}
                    planned.append(plan)
                    result.warnings += translated.warnings.map{"\(plan.name): \($0)"}
                }
                if !planned.isEmpty {result.rack.branches=planned;result.warnings.append("Parallel instrument branches use isolated native sample layers, independent MIDI/effects and a shared parent mix. Saved selector state and branch levels remain baked into the sample maps; live selector automation is not translated.")}
                for device in preset.all("Device").flatMap(\.children) {handled.insert(ObjectIdentifier(device))}
                return []
            }
            if let mixer=branches[0].at("MixerPreset/AbletonDevicePreset/Device/AudioBranchMixerDevice"),!mixer.flag("Speaker/Manual",true){return []}
            var devices=try (branches[0].at("DevicePresets")?.children ?? []).flatMap{try expand($0,owner,depth+1)}
            if let mixer=branches[0].at("MixerPreset/AbletonDevicePreset/Device/AudioBranchMixerDevice") {
                if branches[0].name == "AudioEffectBranchPreset" {
                    if try mixer.number("Volume/Manual",1) != 1 || mixer.string("Volume/KeyMidi/Channel") == "16" {devices.append((mixer,owner))}
                    if try mixer.number("Pan/Manual",0) != 0 {result.warnings.append("Audio-effect rack branch pan is not translated.")}
                } else if try mixer.number("Volume/Manual",1) != 1 {result.warnings.append("Instrument branch gain remains baked into samples before translated processing; nonlinear processors can respond differently.")}
            }
            return devices
        }
        let preset=entry ?? root.at("GroupDevicePreset") ?? root.at("AbletonDevicePreset")
        let scoped=try preset.map{try expand($0,nil,0)} ?? []
        let chain=scoped.map(\.device)
        var macroOwners:[Int:(node:Node,local:Int,scope:Int)]=[:]
        var bindings:[Int:[ImportedMacroBinding]]=[:]
        func value(_ node:Node,_ path:String,_ fallback:Double=0)throws->Float {Float(try node.number(path+"/Manual",fallback))}
        for (device,owner) in scoped {
            if let stage=audioPlans[ObjectIdentifier(device)] {
                let stageIndex=result.rack.audioRacks?.count ?? 0
                var plans=stage.branches
                if let owner=stage.owner {
                    for i in plans.indices {
                        let localMacros=plans[i].rack.macros.filter{stage.ownedMacros[i].contains($0.index)}
                        for macro in localMacros {audioPromoted.append((owner,macro,[stageIndex,i]))}
                        plans[i].rack.macros.removeAll{m in localMacros.contains(where:{$0.index==m.index})}
                    }
                }
                result.rack.audioRacks=(result.rack.audioRacks ?? [])+[ImportedAudioRack(beforeEffect:result.rack.effects.count,name:stage.name,branches:plans)]
                continue
            }
            let kind:Int
            switch device.name {case "FilterEQ3":kind=7;case "Compressor2":kind=6;case "Reverb":kind=13;case "CrossDelay","PingPongDelay":kind=3;case "AudioBranchMixerDevice","StereoGain":kind=9;default:continue}
            guard result.rack.effects.count<12 else{result.warnings.append("Rack effect limit reached; remaining processors are not translated.");break}
            var fx=AudioEffect();fx.kind=kind;fx.enabled=device.flag("On/Manual",true)
            var values=AudioEffectCatalog.defaults(for:kind)
            let slot=result.rack.effects.count
            func map(_ source:String,_ index:Int,_ fallback:Double=0,logarithmic:Bool=false,_ transform:(Float)->Float = {$0})throws {
                guard let descriptor=AudioEffectCatalog.descriptors(for:kind).first(where:{$0.index==index}) else{return}
                func clean(_ raw:Float)->Float {max(descriptor.minimum,min(descriptor.maximum,transform(raw)))}
                values[index]=clean(try value(device,source,fallback))
                guard let owner,let scope=owners.firstIndex(where:{$0 === owner}),scope<16,let key=device.at(source+"/KeyMidi"),key.string("Channel") == "16" else{return}
                let macro=Int(try key.number("NoteOrController",-1))
                guard (0..<8).contains(macro),let range=device.at(source+"/MidiControllerRange") else{return}
                let low=clean(Float(try range.number("Min"))),high=clean(Float(try range.number("Max")))
                let macroID=scope*8+macro
                macroOwners[macroID]=(owner,macro,scope)
                bindings[macroID,default:[]].append(.init(effect:slot,parameter:index,minimum:low,maximum:high,logarithmic:logarithmic && low>0 && high>0))
            }
            switch kind {
            case 9:
                try map(device.name == "StereoGain" ? "Gain":"Volume",0,1){20*log10(max(0.00001,$0))}
            case 3:
                guard !device.flag("Freeze/Manual") else{result.warnings.append("Frozen delay is not translated.");continue}
                func time(_ synced:Bool,_ enumeration:String,_ offset:String,_ milliseconds:String)throws->Double {
                    if !synced {return max(0.001,min(5.334,try device.number(milliseconds+"/Manual",100)/1000))}
                    let choices:[Double]=[1,2,3,4,5,6,8,16]
                    let index=Int(try device.number(enumeration+"/Manual",0))
                    guard choices.indices.contains(index) else{throw AbletonImportError.invalid("Unknown delay beat division." )}
                    let adjustment=try device.number(offset+"/Manual",0)/100
                    guard (-0.3334...0.3334).contains(adjustment) else{throw AbletonImportError.invalid("Unsupported delay time offset.")}
                    return choices[index]/4*(1+adjustment)
                }
                let ping=device.name == "PingPongDelay"
                let ls=device.flag(ping ? "DelayModeSwitch/Manual":"SyncModeLeft/Manual",true)
                let linked=device.flag("Linked/Manual"),rs=ping || linked ? ls:device.flag("SyncModeRight/Manual",true)
                let left=try time(ls,ping ? "BeatDelayTime":"BeatDelayEnumL",ping ? "BeatDelayOffset":"NoteOffsetLeft",ping ? "MsDelayTime":"MsDelayLeft")
                let right=ping || linked ? left:try time(rs,"BeatDelayEnumR","NoteOffsetRight","MsDelayRight")
                var delay=ImportedDelay(left:left,right:right,leftSynced:ls,rightSynced:rs,pingPong:ping)
                if ping {let frequency=try value(device,"MidFreq",1000),width=try value(device,"BandWidth",4);delay.lowCut=max(20,min(20000,frequency/pow(2,width/2)));delay.highCut=max(delay.lowCut,min(20000,frequency*pow(2,width/2)))}
                fx.importedDelay=delay
                try map("Feedback",0,0.3);try map("DryWet",3,0.5)
                values[1]=Float(min(2,max(0.0625,left)));values[2]=delay.highCut
                result.warnings.append("Stereo delay preserves saved left/right beat or millisecond times, offsets, feedback and blend. Ping-pong uses cross-feedback; filter shape and time-change transitions differ. Delay time is bounded to 16 seconds.")
            case 7:
                // Shelf + broad mid-band approximation; EQ3's crossover topology differs.
                try map("FreqLo",3,250,logarithmic:true)
                try map("FreqHi",18,2500,logarithmic:true)
                try map("GainLo",4,1){20*log10(max(0.00001,$0))}
                try map("GainMid",7,1){20*log10(max(0.00001,$0))}
                try map("GainHi",19,1){20*log10(max(0.00001,$0))}
                values[6]=sqrt(values[3]*values[18]);values[8]=0.707
                for (key,index) in [("LowOn",4),("MidOn",7),("HighOn",19)] where !device.flag(key+"/Manual",true) {values[index] = -24}
                result.warnings.append("EQ3 uses a shelf/mid-band approximation; crossover slopes and band kills differ.")
            case 6:
                try map("Attack",1,20);try map("Release",2,60);try map("Ratio",3,2)
                try map("Threshold",4,1){20*log10(max(0.00001,$0))}
                try map("DryWet",5,1);try map("Gain",6,0)
                result.warnings.append("Compressor attack, release, ratio, threshold, blend and output gain translated; detector, knee, lookahead and automatic makeup differ.")
            case 13:
                try map("RoomSize",0,50){$0/100};try map("PreDelay",1,0)
                try map("BandFreq",3,100);try map("ShelfHiFreq",4,20000)
                if !device.flag("BandLowOn/Manual",true){values[3]=20}
                if !device.flag("ShelfHighOn/Manual",true){values[4]=20000}
                try map("SizeModDepth",5,0);try map("SizeModFreq",6,1)
                if !device.flag("ChorusOn/Manual",true){values[5]=0}
                try map("MixDirect",7,0){1-$0};try map("MixDirect",8,0)
                // Decay time is retained as an approximation to feedback, not an exact RT60.
                values[2]=max(0,min(0.95,1-exp(-Float(try device.number("DecayTime/Manual",1000))/2000)))
                result.warnings.append("Reverb uses PrimaVerb with saved size, predelay, tone, modulation and dry/wet controls. Decay and stereo/diffusion behavior are approximate; freeze is not translated.")
            default:break
            }
            fx.parameters=values;result.rack.effects.append(fx);handled.insert(ObjectIdentifier(device))
        }
        for item in promoted {
            guard let scope=owners.firstIndex(where:{$0 === item.owner}),scope<16 else{continue}
            let local=item.macro.index%8,id=scope*8+local
            macroOwners[id]=(item.owner,local,scope)
            for var binding in item.macro.bindings {binding.branchPath=item.path+(binding.branchPath ?? []);bindings[id,default:[]].append(binding)}
        }
        for item in audioPromoted {
            guard let scope=owners.firstIndex(where:{$0 === item.owner}),scope<16 else{continue}
            let local=item.macro.index%8,id=scope*8+local;macroOwners[id]=(item.owner,local,scope)
            for var binding in item.macro.bindings {binding.audioPath=item.path+(binding.audioPath ?? []);bindings[id,default:[]].append(binding)}
        }
        for index in bindings.keys.sorted() {
            guard let macro=macroOwners[index] else{continue}
            let localName=macro.node.string("MacroDisplayNames.\(macro.local)","Macro \(macro.local+1)")
            let name=macro.scope==0 ? localName : "Rack \(macro.scope+1) · \(localName)"
            let saved=Float(try macro.node.number("MacroControls.\(macro.local)/Manual",0))
            result.macroSources[index]=ObjectIdentifier(macro.node)
            result.rack.macros.append(.init(index:index,name:name,value:max(0,min(127,saved)),bindings:bindings[index]!))
        }
        if !bindings.isEmpty {result.warnings.append("Mapped effect macros are available in Sound Controls. Frequency ranges interpolate logarithmically; other translated ranges interpolate linearly. Only translated effect targets are connected; sampler, delay-time and other unmapped macro targets remain unsupported.")}
        let midi=chain.filter{["MidiPitcher","MidiChord"].contains($0.name) && $0.flag("On/Manual",true)}
        if !midi.isEmpty {
            var mappings=(0...127).map{MIDIChordMapping(input:$0,output:[$0])},supported=true
            for device in midi {
                if device.name == "MidiPitcher" {
                    let pitch=Int(try value(device,"Pitch")),lowest=Int(try value(device,"Lowest")),range=Int(try value(device,"Range",127))
                    for i in mappings.indices {mappings[i].output=mappings[i].output.filter{(lowest...max(lowest,lowest+range)).contains($0)}.map{$0+pitch}.filter{(0...127).contains($0)}}
                } else {
                    var shifts=[0]
                    for n in 1...6 {let shift=Int(try value(device,"Shift\(n)"));if shift != 0 {shifts.append(shift);if try value(device,"Velocity\(n)",1) != 1 {supported=false}}}
                    for i in mappings.indices {mappings[i].output=Array(Set(mappings[i].output.flatMap{note in shifts.map{note+$0}})).filter{(0...127).contains($0)}.sorted()}
                }
            }
            let otherMIDI=chain.contains{$0.name.hasPrefix("Midi") && !["MidiPitcher","MidiChord"].contains($0.name) && $0.flag("On/Manual",true)}
            if supported && !otherMIDI {var program=MIDIProgram();program.kind = .easyChord;program.chordMappings=mappings;result.midi=program.validated;for device in midi{handled.insert(ObjectIdentifier(device))}}
            else {result.warnings.append("This MIDI chain includes velocity-scaled chord voices or additional MIDI processors; the chain is not translated.")}
        }
        // Identity velocity devices can safely be omitted without blocking a neighboring arp.
        for device in chain where device.name == "MidiVelocity" && device.flag("On/Manual",true) {
            if try value(device,"Drive")==0 && value(device,"Compand")==0 && value(device,"Random")==0 && value(device,"MaxOut",127)==127 && value(device,"MinOut",1)<=1 && value(device,"Lowest",1)<=1 && value(device,"Range",127)>=127 {handled.insert(ObjectIdentifier(device))}
        }
        let arps=chain.filter{$0.name == "MidiArpeggiator" && $0.flag("On/Manual",true)}
        if arps.count==1,chain.filter({$0.name.hasPrefix("Midi") && $0.flag("On/Manual",true) && !handled.contains(ObjectIdentifier($0))}).count==1 {
            let arp=arps[0]
            let styles:[Int:MIDIArpStyle]=[0:.up,1:.down,2:.upDown,3:.downUp,13:.asPlayed,14:.chord,15:.random]
            if let style=styles[Int(try value(arp,"Mode"))] {
                var program=MIDIProgram();program.kind = .arpeggiator;program.style=style
                if arp.flag("SyncState/Manual",true) {
                    // Historical 14-value Live rate chooser: 1/128, 1/96, ... 1/2, 1/1.
                    let divisions:[Double]=[128,96,64,48,32,24,16,12,8,6,4,3,2,1]
                    let index=Int(try value(arp,"SyncedRate",6))
                    guard divisions.indices.contains(index) else{throw AbletonImportError.invalid("Unknown arpeggiator rate.")}
                    program.subdivision=4/divisions[index]
                } else {program.freeRateSeconds=Double(try value(arp,"FreeRate",20))/1000}
                let groove=Int(try value(arp,"Groove"))
                if (1...3).contains(groove){program.swingGridBeats=[0.5,0.25,0.125][groove-1];program.swingAmount=0;result.warnings.append("Groove choice retained. Global groove amount is not stored in this preset; swing starts at zero and can be set in the MIDI editor. Swing is a conventional timing approximation, not a Live groove-pool file.")}
                else if groove != 0 {result.warnings.append("Unknown groove chooser value is not translated.")}
                program.gate=Double(try value(arp,"Gate",50))/100
                program.hold=arp.flag("Hold/Manual");program.retriggerOnNote=(try value(arp,"Retrigger"))==1
                program.patternOffset=Int(try value(arp,"PatternOffset"));program.releaseGeneratedOnKeyUp=false
                let repeats=Int(try value(arp,"RepeatCount"));if repeats>0 {program.repeatCount=repeats}
                if try value(arp,"Retrigger")==2 {
                    let divisions:[Double]=[128,96,64,48,32,24,16,12,8,6,4,3,2,1,0.5,0.25,0.125,0.0625]
                    let index=Int(try value(arp,"RetriggerInterval",8));if divisions.indices.contains(index){program.retriggerBeats=4/divisions[index]}
                }
                if arp.flag("VelocitySwitch/Manual") {program.velocityTarget=try value(arp,"VelocityTarget",64)/127;program.velocityDecaySeconds=Double(try value(arp,"VelocityDecay",1000))/1000;program.retriggerVelocity=arp.flag("RetriggerVelocity/Manual")}
                if try value(arp,"TransposeMode")==0 {program.transposeSteps=Int(try value(arp,"TransposeSteps"));program.transposeDistance=Int(try value(arp,"TransposeDistance",12))}
                result.midi=program.validated;handled.insert(ObjectIdentifier(arp))
                result.warnings.append("Arpeggiator style, rate, gate, hold, offset and note retrigger translated. Historical numeric style/rate mapping is inferred from the saved chooser format and needs comparison in Live. Finite repeats and chromatic transposition are retained; velocity decay uses a linear approximation. Beat retrigger is relative to the first played note rather than Live song position. Live groove-pool templates, scale transposition and unsupported styles are not translated; scheduler timing is not sample-accurate.")
            }
        }
        if let branches=result.rack.branches,let layerMapping {
            let scopedDevices=(entry ?? root).all("OriginalSimpler")+(entry ?? root).all("MultiSampler")
            let expected=Set(scopedDevices.compactMap{layerMapping[ObjectIdentifier($0)]})
            if Set(branches.flatMap(\.sampleLayers)) != expected {result.rack.branches=nil;for i in result.rack.macros.indices {result.rack.macros[i].bindings.removeAll{!($0.branchPath ?? []).isEmpty}};result.rack.macros.removeAll{$0.bindings.isEmpty};result.warnings.append("Incomplete parallel layer coverage: combined sample playback retained instead of dropping a layer.")}
        }
        let excluded:Set<String>=["OriginalSimpler","MultiSampler","InstrumentGroupDevice","AudioBranchMixerDevice","MidiBranchMixerDevice"]
        let all=(entry ?? root).all("Device").flatMap(\.children).filter{!excluded.contains($0.name) && $0.flag("On/Manual",true) && !handled.contains(ObjectIdentifier($0))}
        if !all.isEmpty {result.warnings.append("Not translated (including nested branch processing): "+Set(all.map(\.name)).sorted().joined(separator:", ")+".")}
        return result
    }
}
