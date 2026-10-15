import Foundation
import AVFoundation
import AudioToolbox

extension ExternalAUIdentity {
    var description: AudioComponentDescription {
        AudioComponentDescription(componentType: type, componentSubType: subtype,
                                  componentManufacturer: manufacturer, componentFlags: 0, componentFlagsMask: 0)
    }
}

enum ExternalInstrumentError: LocalizedError {
    case unsupportedFormat, missingFile, invalidComponent, invalidChannel, superseded, unsupportedEffect
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Import SF2, DLS, Apple sampler AUPRESET/EXS, WAV, AIFF, AIF, or CAF files. VST and Kontakt libraries require a compatible Audio Unit."
        case .missingFile: return "The imported sound file is missing. Import it again on this device."
        case .invalidComponent: return "This Audio Unit is not a playable MIDI instrument or is unavailable on this device."
        case .invalidChannel: return "The sound module is unavailable."
        case .unsupportedEffect: return "This effect is not available for imported instruments. Choose a supported native effect."
        case .superseded: return "A newer sound selection replaced this request."
        }
    }
}

/// A private instrument branch: independent sample voices, MIDI scheduler and effect state.
private final class ImportedBranchVoice {
    let output=AVAudioMixerNode()
    let sum=AVAudioMixerNode()
    var sampler:AVAudioUnitSampler?
    var children:[ImportedBranchVoice]=[]
    var banks:[AVAudioUnitEffect]=[]
    let midi=MIDIFXProcessor()
    var plan:ImportedBranch
    var pitches:[Int:UInt8]=[:]
    init(_ plan:ImportedBranch){self.plan=plan}
    func configure(_ plan:ImportedBranch,tempo:Float) {
        self.plan=plan;output.pan=plan.pan;output.outputVolume=plan.enabled != false ? (plan.gain ?? 1):0
        var program=plan.midi ?? MIDIProgram();if plan.midiEnabled == false {program.kind = .bypass}
        midi.configure(channel:0,program:program,tempo:Double(tempo))
        for (index,child) in children.enumerated(){child.configure(plan.rack.branches![index],tempo:tempo)}
        for (index,bank) in banks.enumerated() {for slot in 0..<3 {
            let i=index*3+slot,fx=i<plan.rack.effects.count ? plan.rack.effects[i]:AudioEffect()
            (bank.auAudioUnit as? BuiltinEffectUnit)?.configure(slot:slot,kind:fx.kind,enabled:fx.enabled,values:fx.values,tempo:tempo,delay:fx.importedDelay)
        }}
    }
    func noteOn(_ key:Int,_ pitch:Int,_ velocity:Float,_ source:Int32?) {
        let v=Int((velocity*127).rounded())
        guard (plan.low...plan.high).contains(pitch),(plan.velocityLow...plan.velocityHigh).contains(v) else{return}
        midi.noteOn(channel:0,key:key,pitch:pitch,velocity:velocity,sourceID:source)
    }
    func sendNote(_ key:Int,_ pitch:Int,_ velocity:Float,_ source:Int32?) {
        if let sampler {pitches[key]=UInt8(pitch);sampler.startNote(UInt8(pitch),withVelocity:UInt8(max(1,min(127,Int(velocity*127)))),onChannel:0)}
        for child in children{child.noteOn(key,pitch,velocity,source)}
    }
    func sendOff(_ key:Int,_ force:Bool){
        if let note=pitches.removeValue(forKey:key){sampler?.stopNote(note,onChannel:0)}
        for child in children{child.midi.noteOff(channel:0,key:key,force:force)}
    }
    func control(_ controller:UInt8,_ value:UInt8){sampler?.sendController(controller,withValue:value,onChannel:0);children.forEach{$0.control(controller,value)}}
    func releaseSource(_ source:Int32){midi.releaseSource(source);children.forEach{$0.releaseSource(source)}}
    func advance(_ time:Double){midi.advance(to:time);children.forEach{$0.advance(time)}}
    func panic(){midi.panic();children.forEach{$0.panic()};sampler?.sendController(64,withValue:0,onChannel:0);sampler?.sendController(120,withValue:0,onChannel:0);pitches.removeAll();banks.forEach{$0.auAudioUnit.reset()}}
}

/// All methods run on the main thread, never in a render callback. Owns no engine.
/// The host must silence held notes before a graph edit and surface thrown errors.
final class ExternalInstrumentRack {
    private let engine: AVAudioEngine
    let libraryURL: URL
    private struct Voice {
        var unit: AVAudioUnit
        var nativePreset:URL? = nil
        var mixer: AVAudioMixerNode
        var filter: AVAudioUnitEQ
        var eq: AVAudioUnitEQ
        var compressor: AVAudioUnitEffect
        var builtin: AVAudioUnitEffect
        var imported: [AVAudioUnitEffect] = []
        var importedDelayLayout:[Bool] = []
        var parallel:[ImportedBranchVoice]=[]
        var parallelNodes:[AVAudioNode]=[]
        var parallelTopology=""
        var pitches: [Int: UInt8] = [:]
    }
    static func supportsEffect(kind: Int) -> Bool { (0...15).contains(kind) }
    /// Legacy names accepted by the adapter; the descriptor API exposes all built-in controls.
    static func supportedEffectParameters(kind: Int) -> Set<String> {
        switch kind {
        case 1: return ["frequency", "resonance", "mix"]
        case 3: return ["feedback", "time", "filter", "mix"]
        case 6: return ["threshold", "attack", "release", "inputGain", "outputGain", "mix"]
        case 7: return Set((0..<8).flatMap { ["frequency\($0)", "gain\($0)", "q\($0)"] })
        case 9: return ["gain"]
        case 11: return ["drive", "mix", "boost"]
        case 12: return ["pitch", "amount"]
        case 13, 15: return ["size", "dry", "wet"]
        default: return []
        }
    }
    static func supportedEffectParameterIndices(kind:Int)->Set<Int> {Set(AudioEffectCatalog.descriptors(for:kind).map(\.index))}
    static func supportedParameters(forKind kind: Int) -> Set<String> {
        let indices = supportedEffectParameterIndices(kind: kind)
        return Set(AudioEffectCatalog.descriptors(for: kind).filter { indices.contains($0.index) }.map { $0.name })
    }
    /// Descriptor-array adapter. Units match AudioEffectCatalog. Tempo is BPM.
    func configureEffect(channel:Int,slot:Int,kind:Int,enabled:Bool,parameters:[Float],tempo:Float=120) throws {
        guard Self.supportsEffect(kind:kind),(0..<3).contains(slot) else {throw ExternalInstrumentError.unsupportedEffect}
        guard let unit=voices[channel]?.builtin.auAudioUnit as? BuiltinEffectUnit else{return}
        unit.configure(slot:slot,kind:kind,enabled:enabled,values:parameters,tempo:tempo)
    }
    private func connectEffects(_ voice:Voice) {
        let format=voice.compressor.outputFormat(forBus:0)
        var previous: AVAudioNode = voice.compressor
        for unit in voice.imported { engine.connect(previous,to:unit,format:format); previous=unit }
        engine.connect(previous,to:voice.builtin,format:format)
        engine.connect(voice.builtin,to:voice.mixer,format:format)
    }
    private static func branchState(_ original:[String:Any],indices:[Int]) throws->[String:Any] {
        guard var instrument=original["Instrument"] as? [String:Any],let layers=instrument["Layers"] as? [[String:Any]],!indices.isEmpty,indices.allSatisfy({layers.indices.contains($0)}) else{throw ExternalInstrumentError.unsupportedFormat}
        var isolated:[[String:Any]]=[];var waveforms=Set<Int>()
        for (newID,index) in indices.enumerated(){
            var layer=layers[index];let oldID=layer["ID"] as? Int ?? index;layer["ID"]=newID
            if var connections=layer["Connections"] as? [[String:Any]] {for i in connections.indices {for key in ["source","destination","control"] {if let value=connections[i][key] as? Int,value>=0x10000000 {connections[i][key]=value+(newID-oldID)*256}}};layer["Connections"]=connections}
            for zone in layer["Zones"] as? [[String:Any]] ?? [] {if let waveform=zone["waveform"] as? Int {waveforms.insert(waveform)}}
            isolated.append(layer)
        }
        instrument["Layers"]=isolated
        var state=original;state["Instrument"]=instrument
        if let refs=state["file-references"] as? [String:String] {state["file-references"]=refs.filter{key,_ in waveforms.contains(Int(key.replacingOccurrences(of:"Sample:",with:"")) ?? -1)}}
        return state
    }
    private func makeBranch(_ plan:ImportedBranch,state:[String:Any],format:AVAudioFormat,tempo:Float,nodes:inout [AVAudioNode])throws->ImportedBranchVoice {
        let voice=ImportedBranchVoice(plan)
        for node in [voice.sum,voice.output] {engine.attach(node);nodes.append(node)}
        if let children=plan.rack.branches {
            for child in children {let nested=try makeBranch(child,state:state,format:format,tempo:tempo,nodes:&nodes);voice.children.append(nested);engine.connect(nested.output,to:voice.sum,format:format)}
        } else {
            let sampler=AVAudioUnitSampler();engine.attach(sampler);nodes.append(sampler);voice.sampler=sampler
            let temporary=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".aupreset")
            defer{try? FileManager.default.removeItem(at:temporary)}
            try PropertyListSerialization.data(fromPropertyList:Self.branchState(state,indices:plan.sampleLayers),format:.xml,options:0).write(to:temporary)
            try sampler.loadInstrument(at:temporary);engine.connect(sampler,to:voice.sum,format:nil)
        }
        var previous:AVAudioNode=voice.sum
        for _ in 0..<((plan.rack.effects.count+2)/3) {let bank=BuiltinEffectUnit.make();engine.attach(bank);nodes.append(bank);voice.banks.append(bank);engine.connect(previous,to:bank,format:format);previous=bank}
        engine.connect(previous,to:voice.output,format:format)
        voice.midi.onNoteWithSource={ [weak voice] _,key,pitch,velocity,source in voice?.sendNote(key,pitch,velocity,source)}
        voice.midi.onOff={ [weak voice] _,key,force in voice?.sendOff(key,force)}
        voice.configure(plan,tempo:tempo)
        return voice
    }
    func configureParallel(channel:Int,branches:[ImportedBranch]?,tempo:Float)throws {
        guard var voice=voices[channel] else{return}
        let topology=(branches ?? []).map(\.topology).joined(separator:";")
        if topology != voice.parallelTopology {
            guard branches == nil || voice.unit is AVAudioUnitSampler else{throw ExternalInstrumentError.unsupportedFormat}
            let state: [String:Any]
            if let file=voice.nativePreset {state=try PropertyListSerialization.propertyList(from:Data(contentsOf:file),options:[],format:nil) as? [String:Any] ?? [:]}
            else {state=voice.unit.auAudioUnit.fullStateForDocument ?? [:]}
            try editGraph {
                var nodes:[AVAudioNode]=[],parallel:[ImportedBranchVoice]=[]
                do {for plan in branches ?? [] {parallel.append(try makeBranch(plan,state:state,format:voice.filter.inputFormat(forBus:0),tempo:tempo,nodes:&nodes))}}
                catch {for node in nodes.reversed(){engine.disconnectNodeOutput(node);engine.detach(node)};throw error}
                voice.parallel.forEach{$0.panic()}
                for node in voice.parallelNodes.reversed(){engine.disconnectNodeOutput(node);engine.detach(node)}
                engine.disconnectNodeOutput(voice.unit)
                if parallel.isEmpty {engine.connect(voice.unit,to:voice.filter,format:nil)}
                else {
                    let mix=AVAudioMixerNode();engine.attach(mix);nodes.append(mix)
                    for branch in parallel {engine.connect(branch.output,to:mix,format:voice.filter.inputFormat(forBus:0))}
                    engine.connect(mix,to:voice.filter,format:voice.filter.inputFormat(forBus:0))
                }
                voice.parallel=parallel;voice.parallelNodes=nodes;voice.parallelTopology=topology;voices[channel]=voice
            }
        }
        for (i,branch) in voice.parallel.enumerated(){branch.configure(branches![i],tempo:tempo)}
    }
    func releaseSource(_ source:Int32){for voice in voices.values {voice.parallel.forEach{$0.releaseSource(source)}}}
    #if DEBUG
    func advanceBranches(to time:Double){for voice in voices.values {voice.parallel.forEach{$0.advance(time)}}}
    func parallelBranchCount(_ channel:Int)->Int {voices[channel]?.parallel.count ?? 0}
    #endif
    func configureImported(channel:Int,effects:[AudioEffect],tempo:Float) throws {
        guard var voice=voices[channel] else{return}
        let count=(min(12,effects.count)+2)/3
        let layout=effects.prefix(12).map{$0.importedDelay != nil}
        func configureBanks() {
            for (bank,unit) in voice.imported.enumerated() {
                guard let builtin=unit.auAudioUnit as? BuiltinEffectUnit else{continue}
                for slot in 0..<3 {
                    let i=bank*3+slot,fx=i<effects.count ? effects[i]:AudioEffect()
                    builtin.configure(slot:slot,kind:fx.kind,enabled:fx.enabled,values:fx.values,tempo:tempo,delay:fx.importedDelay)
                }
            }
        }
        if voice.imported.count != count || voice.importedDelayLayout != layout {
            try editGraph {
                engine.disconnectNodeOutput(voice.compressor)
                for unit in voice.imported {engine.disconnectNodeOutput(unit);engine.detach(unit)}
                voice.imported=(0..<count).map{_ in let unit=BuiltinEffectUnit.make();engine.attach(unit);return unit}
                voice.importedDelayLayout=layout;configureBanks()
                connectEffects(voice);voices[channel]=voice
            }
        }
        configureBanks()
    }

    func configureEffect(channel:Int,slot:Int,kind:Int,enabled:Bool,parameters:[String:Float]) throws {
        var values=AudioEffectCatalog.defaults(for:kind)
        func key(_ value:String)->String {value.lowercased().replacingOccurrences(of:" ",with:"")}
        let normalized=Dictionary(parameters.map{(key($0.key),$0.value)},uniquingKeysWith:{$1})
        for p in AudioEffectCatalog.descriptors(for:kind) {if let value=normalized[key(p.name)] {values[p.index]=value}}
        if kind==3,let time=parameters["time"] {values[1]=time*2}
        if kind==7 {for band in 0..<8 {if let value=parameters["frequency\(band)"]{values[band*3]=value};if let value=parameters["gain\(band)"]{values[band*3+1]=value};if let value=parameters["q\(band)"]{values[band*3+2]=value}}}
        try configureEffect(channel:channel,slot:slot,kind:kind,enabled:enabled,parameters:values,tempo:parameters["Tempo"] ?? 120)
    }
    private var voices: [Int: Voice] = [:]
    private var generations: [Int: UUID] = [:]
    init(engine: AVAudioEngine, libraryURL: URL? = nil) throws {
        self.engine = engine
        let base=ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"].map{URL(fileURLWithPath:$0,isDirectory:true)} ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("StageKeys",isDirectory:true)
        self.libraryURL = libraryURL ?? base.appendingPathComponent("Imported Sounds",isDirectory:true)
        try FileManager.default.createDirectory(at: self.libraryURL, withIntermediateDirectories: true)
    }
    static func instruments() -> [ExternalAUIdentity] {
        let query = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice, componentSubType: 0,
                                             componentManufacturer: 0, componentFlags: 0, componentFlagsMask: 0)
        return AVAudioUnitComponentManager.shared().components(matching: query).map {
            let d = $0.audioComponentDescription
            return ExternalAUIdentity(type: d.componentType, subtype: d.componentSubType,
                                      manufacturer: d.componentManufacturer, name: $0.name)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    /// Copy user-picked files while the document picker security scope is available.
    func importSound(_ url: URL) throws -> ExternalSound {
        precondition(Thread.isMainThread)
        let ext = url.pathExtension.lowercased()
        if ext == "aupreset" { return try importPreset(url, sampleRoot: url.deletingLastPathComponent()) }
        if ext == "exs" { return try importEXS(url, sampleRoot: url.deletingLastPathComponent()) }
        let kind: ExternalSound.Kind
        switch ext {
        case "sf2", "dls": kind = .soundBank
        case "wav", "aiff", "aif", "caf": kind = .sample
        default: throw ExternalInstrumentError.unsupportedFormat
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let filename = UUID().uuidString + "." + ext
        let destination = libraryURL.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: url, to: destination)
        do {
            let sampler = AVAudioUnitSampler()
            if kind == .soundBank {
                try sampler.loadSoundBankInstrument(at: destination, program: 0, bankMSB: 121, bankLSB: 0)
            } else { try loadSample(sampler, url: destination) }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return ExternalSound(kind: kind, name: url.deletingPathExtension().lastPathComponent, fileName: filename)
    }
    /// Convert a user-selected EXS24 instrument through Apple's documented
    /// sampler loader, then relocate only samples within the selected root.
    /// Native EXS resolution may read its original references; this importer
    /// never searches the disk and never copies references outside sampleRoot.
    func importEXS(_ url: URL, sampleRoot: URL) throws -> ExternalSound {
        precondition(Thread.isMainThread)
        guard url.pathExtension.lowercased() == "exs" else { throw ExternalInstrumentError.unsupportedFormat }
        let instrumentAccess = url.startAccessingSecurityScopedResource()
        let sampleAccess = sampleRoot.startAccessingSecurityScopedResource()
        defer {
            if instrumentAccess { url.stopAccessingSecurityScopedResource() }
            if sampleAccess { sampleRoot.stopAccessingSecurityScopedResource() }
        }
        return try EXSCaptureCompatibility.withCompatiblePreset(url,sampleRoot:sampleRoot) { compatible,root in
            var sound=try importCompatibleEXS(compatible,sampleRoot:root)
            sound.name=url.deletingPathExtension().lastPathComponent
            return sound
        }
    }
    private func importCompatibleEXS(_ url:URL,sampleRoot:URL) throws -> ExternalSound {
        let stagingEngine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        stagingEngine.attach(sampler)
        stagingEngine.connect(sampler, to: stagingEngine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        defer { stagingEngine.disconnectNodeOutput(sampler); stagingEngine.detach(sampler) }
        do { try sampler.loadInstrument(at: url) }
        catch {
            // Explicit documented instrument type also handles extensions the
            // AVFoundation filename dispatcher does not recognize.
            let sourceURL = url as CFURL
            var instrument = AUSamplerInstrumentData(fileURL: Unmanaged.passUnretained(sourceURL),
                instrumentType: UInt8(kInstrumentType_EXS24), bankMSB: 0, bankLSB: 0, presetID: 0)
            let code = AudioUnitSetProperty(sampler.audioUnit, kAUSamplerProperty_LoadInstrument,
                kAudioUnitScope_Global, 0, &instrument, UInt32(MemoryLayout<AUSamplerInstrumentData>.size))
            guard code == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(code),
                userInfo: [NSLocalizedDescriptionKey: "Apple's sampler could not load this EXS instrument (\(code)). Its samples may be missing or its format unsupported."]) }
        }
        guard let state = sampler.auAudioUnit.fullStateForDocument,
              let references = state["file-references"] as? [String: String], !references.isEmpty else {
            throw NSError(domain: "StageKeysEXS", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "The EXS instrument loaded without sample references. Its samples may be missing."])
        }
        let stagingPreset = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".aupreset")
        defer { try? FileManager.default.removeItem(at: stagingPreset) }
        try PropertyListSerialization.data(fromPropertyList: state, format: .xml, options: 0).write(to: stagingPreset, options: .atomic)
        var result = try importPreset(stagingPreset, sampleRoot: sampleRoot)
        result.name = url.deletingPathExtension().lastPathComponent
        return result
    }
    /// Imports only an explicitly selected preset and references inside its chosen
    /// sample directory. Missing references require the user to choose a root;
    /// this never searches the disk or copies files outside that root.
    func importPreset(_ url: URL, sampleRoot: URL) throws -> ExternalSound {
        precondition(Thread.isMainThread)
        let presetAccess = url.startAccessingSecurityScopedResource()
        let sampleAccess = sampleRoot.startAccessingSecurityScopedResource()
        defer {
            if presetAccess { url.stopAccessingSecurityScopedResource() }
            if sampleAccess { sampleRoot.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 16 * 1024 * 1024,
              var state = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              (state["type"] as? NSNumber)?.uint32Value == kAudioUnitType_MusicDevice,
              (state["subtype"] as? NSNumber)?.uint32Value == kAudioUnitSubType_Sampler,
              (state["manufacturer"] as? NSNumber)?.uint32Value == kAudioUnitManufacturer_Apple else {
            throw ExternalInstrumentError.unsupportedFormat
        }
        let references = state["file-references"] as? [String: String] ?? [:]
        guard references.count <= 4096 else { throw ExternalInstrumentError.unsupportedFormat }
        let root = sampleRoot.resolvingSymlinksInPath().standardizedFileURL
        let identity = UUID().uuidString
        let assets = libraryURL.appendingPathComponent(identity + "-samples", isDirectory: true)
        let preset = libraryURL.appendingPathComponent(identity + ".aupreset")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        do {
            var rewritten: [String: String] = [:]
            var copied: [URL: URL] = [:]
            for (key, reference) in references {
                let sourcePath = reference.hasPrefix("file://") ? (URL(string: reference)?.path ?? reference) : reference
                let original = URL(fileURLWithPath: sourcePath)
                // Try only exact path suffixes under the explicitly selected
                // sample root. This handles a moved EXS sample subtree without
                // traversing the root or searching other folders.
                let components = original.pathComponents.filter { $0 != "/" && $0 != ".." && $0 != "." }
                let suffixes = (1...max(1, min(16, components.count))).map { count in
                    root.appendingPathComponent(components.suffix(count).joined(separator: "/"))
                }
                let candidates = [original, root.appendingPathComponent(sourcePath)] + suffixes
                guard let source = candidates.map({ $0.resolvingSymlinksInPath().standardizedFileURL }).first(where: {
                    $0.path.hasPrefix(root.path + "/") && FileManager.default.fileExists(atPath: $0.path)
                }), ["wav", "aif", "aiff", "caf", "flac"].contains(source.pathExtension.lowercased()) else {
                    throw NSError(domain: "StageKeysPreset", code: 1, userInfo: [NSLocalizedDescriptionKey:
                        "Missing sample: \(original.lastPathComponent). Choose the preset's sample folder and retry."])
                }
                let destination: URL
                if let existing = copied[source] { destination = existing }
                else {
                    destination = assets.appendingPathComponent(UUID().uuidString + "." + source.pathExtension)
                    try FileManager.default.copyItem(at: source, to: destination)
                    copied[source] = destination
                }
                rewritten[key] = destination.path
            }
            // FullState omits default zone endpoints; the file preset loader
            // does not consistently restore them, so encode them explicitly.
            if var instrument = state["Instrument"] as? [String: Any],
               var layers = instrument["Layers"] as? [[String: Any]] {
                for layer in layers.indices {
                    if var zones = layers[layer]["Zones"] as? [[String: Any]] {
                        for zone in zones.indices {
                            if zones[zone]["min key"] == nil { zones[zone]["min key"] = 0 }
                            if zones[zone]["max key"] == nil { zones[zone]["max key"] = 127 }
                        }
                        layers[layer]["Zones"] = zones
                    }
                }
                instrument["Layers"] = layers
                state["Instrument"] = instrument
            }
            state["file-references"] = rewritten
            try PropertyListSerialization.data(fromPropertyList: state, format: .xml, options: 0).write(to: preset, options: .atomic)
            return ExternalSound(kind: .samplerPreset, name: url.deletingPathExtension().lastPathComponent, fileName: preset.lastPathComponent)
        } catch {
            try? FileManager.default.removeItem(at: preset)
            try? FileManager.default.removeItem(at: assets)
            throw error
        }
    }
    /// Apple infers one-note zones from filenames when no mapping exists. Make
    /// plain audio a chromatic C4 instrument instead of relying on that inference.
    private func loadSample(_ sampler: AVAudioUnitSampler, url: URL) throws {
        try sampler.loadAudioFiles(at: [url])
        guard var state = sampler.auAudioUnit.fullState,
              var instrument = state["Instrument"] as? [String: Any],
              var layers = instrument["Layers"] as? [[String: Any]] else { return }
        for layer in layers.indices {
            guard var zones = layers[layer]["Zones"] as? [[String: Any]] else { continue }
            for zone in zones.indices {
                zones[zone]["min key"] = 0
                zones[zone]["max key"] = 127
                zones[zone]["root key"] = 60
            }
            layers[layer]["Zones"] = zones
        }
        instrument["Layers"] = layers
        state["Instrument"] = instrument
        sampler.auAudioUnit.fullState = state
    }
    #if DEBUG
    func debugBuiltin(_ channel:Int)->AVAudioUnitEffect? {voices[channel]?.builtin}
    #endif
    func contains(_ channel: Int) -> Bool { voices[channel] != nil }
    func load(_ sound: ExternalSound, channel: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        precondition(Thread.isMainThread)
        guard (0..<15).contains(channel) else { completion(.failure(ExternalInstrumentError.invalidChannel)); return }
        let generation = UUID()
        generations[channel] = generation
        if sound.kind == .audioUnit {
            guard let component = sound.component, component.type == kAudioUnitType_MusicDevice else {
                completion(.failure(ExternalInstrumentError.invalidComponent)); return
            }
            AVAudioUnit.instantiate(with: component.description, options: []) { [weak self] unit, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard self.generations[channel] == generation else {
                        completion(.failure(ExternalInstrumentError.superseded)); return
                    }
                    guard let unit, unit.auAudioUnit.scheduleMIDIEventBlock != nil else {
                        completion(.failure(error ?? ExternalInstrumentError.invalidComponent)); return
                    }
                    do { try self.install(unit, channel: channel); completion(.success(())) }
                    catch { completion(.failure(error)) }
                }
            }
        } else {
            do {
                guard let name = sound.fileName, name == URL(fileURLWithPath: name).lastPathComponent else {
                    throw ExternalInstrumentError.missingFile
                }
                let file = libraryURL.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: file.path) else { throw ExternalInstrumentError.missingFile }
                let sampler = AVAudioUnitSampler()
                if sound.kind == .soundBank {
                    try sampler.loadSoundBankInstrument(at: file, program: sound.program, bankMSB: sound.bankMSB, bankLSB: sound.bankLSB)
                } else if sound.kind == .samplerPreset {
                    try install(sampler, channel: channel) { try sampler.loadInstrument(at: file) }
                    voices[channel]?.nativePreset=file
                    completion(.success(()))
                    return
                } else { try loadSample(sampler, url: file) }
                try install(sampler, channel: channel)
                completion(.success(()))
            } catch { completion(.failure(error)) }
        }
    }
    private func mixerState() -> [(AVAudioMixerNode, Float, Float)] {
        var nodes = [engine.mainMixerNode]
        for voice in voices.values {
            nodes.append(voice.mixer)

        }
        return nodes.map { ($0, $0.outputVolume, $0.pan) }
    }
    private func restoreMixers(_ state: [(AVAudioMixerNode, Float, Float)]) {
        for (node, gain, pan) in state where node.engine === engine {
            node.outputVolume = gain; node.pan = pan
        }
    }
    private func editGraph(_ operation: () throws -> Void) throws {
        let mixerSnapshot = mixerState()
        defer { restoreMixers(mixerSnapshot) }
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        do {try operation()} catch {if wasRunning {try? engine.start()};throw error}
        if wasRunning { engine.prepare(); try engine.start() }
    }
    private func install(_ unit: AVAudioUnit, channel: Int, configure: (() throws -> Void)? = nil) throws {
        let mixerSnapshot = mixerState()
        defer { restoreMixers(mixerSnapshot) }
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        engine.attach(unit)
        do { try configure?() } catch {
            engine.detach(unit)
            if wasRunning { engine.prepare(); try? engine.start() }
            throw error
        }
        panic(channel)
        detach(channel)
        let mixer = AVAudioMixerNode()
        let filter = AVAudioUnitEQ(numberOfBands: 1)
        filter.bands[0].filterType = .resonantLowPass
        filter.bands[0].bypass = true
        let eq = AVAudioUnitEQ(numberOfBands: 8)
        for (i, band) in eq.bands.enumerated() {
            band.filterType = i == 0 ? .highPass : i == 1 ? .lowShelf : i == 6 ? .highShelf : i == 7 ? .lowPass : .parametric
            band.bypass = i == 0 || i == 7
        }
        let compressor = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
        compressor.bypass = true
        for node in [mixer as AVAudioNode, filter, eq, compressor] { engine.attach(node) }
        engine.connect(unit, to: filter, format: nil)
        engine.connect(filter, to: eq, format: nil)
        engine.connect(eq, to: compressor, format: nil)
        let builtin=BuiltinEffectUnit.make();engine.attach(builtin)
        let voice = Voice(unit: unit, mixer: mixer, filter: filter, eq: eq, compressor: compressor,builtin:builtin)
        connectEffects(voice)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        voices[channel] = voice
        if wasRunning { engine.prepare(); try engine.start() }
    }
    private func detach(_ channel: Int) {
        guard let old = voices.removeValue(forKey: channel) else { return }
        for node in [old.unit as AVAudioNode, old.filter, old.eq, old.compressor, old.mixer,old.builtin] + old.imported.map({$0 as AVAudioNode}) + old.parallelNodes {
            engine.disconnectNodeOutput(node); engine.detach(node)
        }
    }
    func remove(_ channel: Int) throws {
        precondition(Thread.isMainThread)
        generations[channel] = UUID()
        panic(channel)
        try editGraph { detach(channel) }
    }
    private func midi(_ channel: Int, _ status: UInt8, _ data1: UInt8, _ data2: UInt8) {
        guard let unit = voices[channel]?.unit else { return }
        if let instrument = unit as? AVAudioUnitMIDIInstrument {
            instrument.sendMIDIEvent(status, data1: data1, data2: data2)
            return
        }
        guard let block = unit.auAudioUnit.scheduleMIDIEventBlock else { return }
        var bytes = [status, data1, data2]
        bytes.withUnsafeMutableBufferPointer { block(AUEventSampleTimeImmediate, 0, 3, $0.baseAddress!) }
    }
    func noteOn(channel: Int, key: Int, pitch: Int, velocity: Float,sourceID:Int32? = nil) {
        precondition(Thread.isMainThread)
        guard (0...127).contains(pitch), velocity.isFinite, voices[channel] != nil else { return }
        if let branches=voices[channel]?.parallel,!branches.isEmpty {branches.forEach{$0.noteOn(key,pitch,velocity,sourceID)};return}
        if let previous = voices[channel]?.pitches[key] { midi(channel, 0x80, previous, 0) }
        let note = UInt8(pitch)
        voices[channel]?.pitches[key] = note
        midi(channel, 0x90, note, UInt8(max(1, min(127, Int(velocity * 127)))))
    }
    func noteOff(channel: Int, key: Int, forceRelease: Bool = false) {
        precondition(Thread.isMainThread)
        if let branches=voices[channel]?.parallel,!branches.isEmpty {branches.forEach{$0.midi.noteOff(channel:0,key:key,force:forceRelease)};return}
        if forceRelease { midi(channel, 0xB0, 64, 0) }
        if let note = voices[channel]?.pitches.removeValue(forKey: key) { midi(channel, 0x80, note, 0) }
    }
    func noteOff(key: Int) {
        precondition(Thread.isMainThread)
        for channel in Array(voices.keys) {
            voices[channel]?.parallel.forEach{$0.midi.noteOff(channel:0,key:key)}
            if let note = voices[channel]?.pitches.removeValue(forKey: key) { midi(channel, 0x80, note, 0) }
        }
    }
    func control(channel: Int, controller: UInt8, value: UInt8) { precondition(Thread.isMainThread); guard controller < 128, value < 128 else { return };voices[channel]?.parallel.forEach{$0.control(controller,value)}; midi(channel, 0xB0, controller, value) }
    func sustain(channel: Int, on: Bool) { precondition(Thread.isMainThread); voices[channel]?.parallel.forEach{$0.control(64,on ? 127:0)};midi(channel, 0xB0, 64, on ? 127 : 0) }
    func volume(channel: Int, gain: Float, pan: Float) {
        precondition(Thread.isMainThread)
        voices[channel]?.mixer.outputVolume = max(0, min(4, gain))
        voices[channel]?.mixer.pan = max(-1, min(1, pan))
    }
    /// Audio processing for imported instruments. The host supplies the fader-
    /// interpolated cutoff; instrument envelopes remain the plug-in's own controls.
    func processing(channel: Int, gain: Float, cutoff: Float, resonance: Float,
                    eqEnabled: Bool, bands: [(frequency: Float, gain: Float, q: Float)],
                    compressorEnabled: Bool, threshold: Float, attack: Float, release: Float, makeup: Float) {
        precondition(Thread.isMainThread)
        guard let voice = voices[channel] else { return }
        voice.filter.globalGain = gain > 0 ? max(-96, min(12, 20 * log10(gain))) : -96
        voice.filter.bands[0].frequency = max(20, min(20000, cutoff))
        voice.filter.bands[0].bandwidth = max(0.05, min(5, 1 / max(0.1, resonance)))
        voice.filter.bands[0].bypass = cutoff >= 19999
        voice.eq.bypass = !eqEnabled
        for (index, band) in bands.prefix(8).enumerated() {
            voice.eq.bands[index].bypass = index == 0 && band.frequency <= 20 || index == 7 && band.frequency >= 20000
            voice.eq.bands[index].frequency = max(20, min(20000, band.frequency))
            voice.eq.bands[index].gain = max(-24, min(24, band.gain))
            // AVAudioUnitEQ uses octaves, while the UI uses Q.
            voice.eq.bands[index].bandwidth = max(0.05, min(5, 2 * asinh(1 / (2 * max(0.1, band.q))) / log(2)))
        }
        voice.compressor.bypass = !compressorEnabled
        let parameters: [(AudioUnitParameterID, Float)] = [
            (kDynamicsProcessorParam_Threshold, threshold),
            (kDynamicsProcessorParam_AttackTime, attack),
            (kDynamicsProcessorParam_ReleaseTime, release),
            (kDynamicsProcessorParam_OverallGain, makeup)
        ]
        for (parameter, value) in parameters {
            AudioUnitSetParameter(voice.compressor.audioUnit, parameter, kAudioUnitScope_Global, 0, value, 0)
        }
    }
    func stateData(channel: Int) throws -> Data? {
        guard let state = state(channel: channel) else { return nil }
        return try PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0)
    }
    func restoreStateData(_ data: Data, channel: Int) throws {
        guard data.count <= 2_000_000,
              let state = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw ExternalInstrumentError.unsupportedFormat
        }
        try editGraph {
            panic(channel)
            restoreState(state, channel: channel)
        }
    }
    func panic(_ channel: Int? = nil) {
        precondition(Thread.isMainThread)
        for index in channel.map({ [$0] }) ?? Array(voices.keys) {
            voices[index]?.parallel.forEach{$0.panic()}
            midi(index, 0xB0, 64, 0)
            for note in voices[index]?.pitches.values ?? Dictionary<Int, UInt8>().values { midi(index, 0x80, note, 0) }
            midi(index, 0xB0, 123, 0); midi(index, 0xB0, 120, 0)
            voices[index]?.pitches.removeAll()
            voices[index]?.builtin.auAudioUnit.reset()
            voices[index]?.imported.forEach{$0.auAudioUnit.reset()}
        }
    }
    func unit(channel: Int) -> AVAudioUnit? { voices[channel]?.unit }
    func state(channel: Int) -> [String: Any]? { voices[channel]?.unit.auAudioUnit.fullStateForDocument }
    func restoreState(_ state: [String: Any], channel: Int) {
        precondition(Thread.isMainThread)
        voices[channel]?.unit.auAudioUnit.fullStateForDocument = state
    }
}
