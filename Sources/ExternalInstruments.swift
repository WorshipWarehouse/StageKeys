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
    var audioGraph:ImportedAudioGraph?
    let midi=MIDIFXProcessor()
    var plan:ImportedBranch
    var pitches:[Int:UInt8]=[:]
    var controllers:[Int:Int]=[:]
    init(_ plan:ImportedBranch){self.plan=plan}
    func configure(_ plan:ImportedBranch,tempo:Float) {
        self.plan=plan;output.pan=plan.pan;output.outputVolume=plan.enabled != false ? (plan.gain ?? 1):0
        var program=plan.midi ?? MIDIProgram();if plan.midiEnabled == false {program.kind = .bypass}
        midi.configure(channel:0,program:program,tempo:Double(tempo))
        for (index,child) in children.enumerated(){child.configure(plan.rack.branches![index],tempo:tempo)}
        audioGraph?.configure(plan.rack,tempo:tempo)

    }
    func noteOn(_ key:Int,_ pitch:Int,_ velocity:Float,_ source:Int32?) {
        let v=Int((velocity*127).rounded())
        guard plan.enabled != false,plan.controllerGate?.accepts(controllers) ?? true,(plan.low...plan.high).contains(pitch),(plan.velocityLow...plan.velocityHigh).contains(v) else{return}
        midi.noteOn(channel:0,key:key,pitch:pitch,velocity:velocity,sourceID:source)
    }
    func sendNote(_ key:Int,_ pitch:Int,_ velocity:Float,_ source:Int32?) {
        if let sampler {pitches[key]=UInt8(pitch);sampler.startNote(UInt8(pitch),withVelocity:UInt8(max(1,min(127,Int((velocity*127).rounded())))),onChannel:0)}
        for child in children{child.noteOn(key,pitch,velocity,source)}
    }
    func sendOff(_ key:Int,_ force:Bool){
        if let note=pitches.removeValue(forKey:key){sampler?.stopNote(note,onChannel:0)}
        for child in children{child.midi.noteOff(channel:0,key:key,force:force)}
    }
    func control(_ controller:UInt8,_ value:UInt8){controllers[Int(controller)]=Int(value);sampler?.sendController(controller,withValue:value,onChannel:0);children.forEach{$0.control(controller,value)}}
    func releaseSource(_ source:Int32){midi.releaseSource(source);children.forEach{$0.releaseSource(source)}}
    func advance(_ time:Double){midi.advance(to:time);children.forEach{$0.advance(time)}}
    func prepareOffline()throws {if let sampler{try SamplerRendering.configure(sampler,offline:true)};for child in children{try child.prepareOffline()}}
    func panic(preserveEffectTails:Bool=false){controllers[64]=0;midi.panic();children.forEach{$0.panic(preserveEffectTails:preserveEffectTails)};sampler?.sendController(64,withValue:0,onChannel:0);sampler?.sendController(preserveEffectTails ? 123:120,withValue:0,onChannel:0);pitches.removeAll();if !preserveEffectTails {audioGraph?.reset()}}
}

/// All methods run on the main thread, never in a render callback. Owns no engine.
/// The host must silence held notes before a graph edit and surface thrown errors.
final class ExternalInstrumentRack {
    private static var recoveryStores:[String:PluginLoadRecovery]=[:]
    private static func loadRecovery()throws->PluginLoadRecovery {
        precondition(Thread.isMainThread)
        let base=ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"].map{URL(fileURLWithPath:$0)} ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("StageKeys")
        let url=base.appendingPathComponent("plugin-load-recovery.json")
        if let existing=recoveryStores[url.path]{return existing}
        let recovery=try PluginLoadRecovery(url:url);recoveryStores[url.path]=recovery;return recovery
    }
    static func allowBlockedLoads()throws {try loadRecovery().allowBlockedLoads()}
    private let engine: AVAudioEngine
    private var controllerValues:[Int:[Int:Int]]=[:]
    let libraryURL: URL
    private struct Voice {
        var unit: AVAudioUnit
        var nativePreset:URL? = nil
        var attackMinimum:Float=0
        var hostVelocityCurve:Int?
        var mixer: AVAudioMixerNode
        var filter: AVAudioUnitEQ
        var eq: AVAudioUnitEQ
        var compressor: AVAudioUnitEffect
        var builtin: AVAudioUnitEffect
        var imported: [AVAudioUnitEffect] = []
        var audioGraph:ImportedAudioGraph?
        var importedDelayLayout:[Bool] = []
        var parallel:[ImportedBranchVoice]=[]
        var parallelNodes:[AVAudioNode]=[]
        var parallelTopology=""
        var pitches: [Int: UInt8] = [:]
    }
    static func supportsEffect(kind: Int) -> Bool { (0...17).contains(kind) }
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
    func configureEffect(channel:Int,slot:Int,kind:Int,enabled:Bool,parameters:[Float],tempo:Float=120,delay:ImportedDelay?=nil) throws {
        guard Self.supportsEffect(kind:kind),(0..<3).contains(slot) else {throw ExternalInstrumentError.unsupportedEffect}
        guard let unit=voices[channel]?.builtin.auAudioUnit as? BuiltinEffectUnit else{return}
        unit.configure(slot:slot,kind:kind,enabled:enabled,values:parameters,tempo:tempo,delay:delay)
    }
    private func connectEffects(_ voice:Voice) {
        let format=voice.compressor.outputFormat(forBus:0)
        var previous: AVAudioNode = voice.compressor
        if let graph=voice.audioGraph {engine.connect(previous,to:graph.input,format:format);previous=graph.output}
        else {for unit in voice.imported { engine.connect(previous,to:unit,format:format); previous=unit }}
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
            for (bus,child) in children.enumerated() {let nested=try makeBranch(child,state:state,format:format,tempo:tempo,nodes:&nodes);voice.children.append(nested);engine.connect(nested.output,to:voice.sum,fromBus:0,toBus:AVAudioNodeBus(bus),format:format)}
        } else {
            let sampler=AVAudioUnitSampler();try SamplerRendering.configure(sampler,offline:engine.isInManualRenderingMode,resident:state["StageKeys.NativeSampler"] != nil);engine.attach(sampler);nodes.append(sampler);voice.sampler=sampler
            let temporary=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".aupreset")
            defer{try? FileManager.default.removeItem(at:temporary)}
            let document=try SamplerSplitRegions.prepare(Self.branchState(state,indices:plan.sampleLayers))
            try PropertyListSerialization.data(fromPropertyList:document,format:.xml,options:0).write(to:temporary)
            try sampler.loadInstrument(at:temporary);rememberSampler(sampler,document:document);engine.connect(sampler,to:voice.sum,format:format)
        }
        let graph=ImportedAudioGraph(engine:engine,rack:plan.rack,format:format,tempo:tempo)
        voice.audioGraph=graph;nodes += graph.nodes
        engine.connect(voice.sum,to:graph.input,format:format);engine.connect(graph.output,to:voice.output,format:format)
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
            if let file=voice.nativePreset {state=try SamplerHostVelocity.prepare(SamplerSplitRegions.prepare(SamplerAttack.prepare(try PropertyListSerialization.propertyList(from:Data(contentsOf:file),options:[],format:nil) as? [String:Any] ?? [:],minimum:voice.attackMinimum)),curve:voice.hostVelocityCurve)}
            else {state=voice.unit.auAudioUnit.fullStateForDocument ?? [:]}
            try editGraph {
                var nodes:[AVAudioNode]=[],parallel:[ImportedBranchVoice]=[]
                do {for plan in branches ?? [] {parallel.append(try makeBranch(plan,state:state,format:voice.filter.inputFormat(forBus:0),tempo:tempo,nodes:&nodes))}}
                catch {for node in nodes.reversed(){engine.disconnectNodeOutput(node);engine.detach(node)};throw error}
                voice.parallel.forEach{$0.panic()}
                for (controller,value) in controllerValues[channel] ?? [:] {parallel.forEach{$0.control(UInt8(controller),UInt8(value))}}
                for node in voice.parallelNodes.reversed(){engine.disconnectNodeOutput(node);engine.detach(node)}
                engine.disconnectNodeOutput(voice.unit)
                if parallel.isEmpty {engine.connect(voice.unit,to:voice.filter,format:nil)}
                else {
                    let mix=AVAudioMixerNode();engine.attach(mix);nodes.append(mix)
                    for (bus,branch) in parallel.enumerated() {engine.connect(branch.output,to:mix,fromBus:0,toBus:AVAudioNodeBus(bus),format:voice.filter.inputFormat(forBus:0))}
                    engine.connect(mix,to:voice.filter,format:voice.filter.inputFormat(forBus:0))
                }
                voice.parallel=parallel;voice.parallelNodes=nodes;voice.parallelTopology=topology;voices[channel]=voice
            }
        }
        for (i,branch) in voice.parallel.enumerated(){branch.configure(branches![i],tempo:tempo)}
    }
    func prepareOfflineSamples()throws {
        for voice in voices.values {if let sampler=voice.unit as? AVAudioUnitSampler {try SamplerRendering.configure(sampler,offline:true)};for branch in voice.parallel {try branch.prepareOffline()}}
    }
    func releaseSource(_ source:Int32){for voice in voices.values {voice.parallel.forEach{$0.releaseSource(source)}}}
    #if DEBUG
    func advanceBranches(to time:Double){for voice in voices.values {voice.parallel.forEach{$0.advance(time)}}}
    func debugBranchStates(_ channel:Int)->[[String:Any]] {voices[channel]?.parallel.compactMap{$0.sampler?.auAudioUnit.fullStateForDocument} ?? []}
    func parallelBranchCount(_ channel:Int)->Int {voices[channel]?.parallel.count ?? 0}
    #endif
    func configureImported(channel:Int,effects:[AudioEffect],tempo:Float)throws {
        try configureImported(channel:channel,rack:ImportedRack(effects:effects),tempo:tempo)
    }
    func configureImported(channel:Int,rack:ImportedRack?,tempo:Float)throws {
        guard var voice=voices[channel] else{return}
        let plan=rack ?? ImportedRack()
        if voice.audioGraph?.topology != plan.audioTopology {
            try editGraph {
                let graph=ImportedAudioGraph(engine:engine,rack:plan,format:voice.compressor.outputFormat(forBus:0),tempo:tempo)
                engine.disconnectNodeOutput(voice.compressor)
                if let old=voice.audioGraph {for node in old.nodes.reversed(){engine.disconnectNodeOutput(node);engine.detach(node)}}
                for node in voice.imported {engine.disconnectNodeOutput(node);engine.detach(node)}
                voice.imported=[];voice.audioGraph=graph
                connectEffects(voice);voices[channel]=voice
            }
        }
        voice.audioGraph?.configure(plan,tempo:tempo)
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
    /// Enumerate installed Audio Units with the metadata the picker needs. Audio
    /// Units installed while StageKeys is running may need a relaunch: Core Audio
    /// provides no public rescan API, so this re-queries the component manager.
    static func instruments() -> [ExternalAUIdentity] {
        let query = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice, componentSubType: 0,
                                             componentManufacturer: 0, componentFlags: 0, componentFlagsMask: 0)
        let identities = AVAudioUnitComponentManager.shared().components(matching: query).map { component -> ExternalAUIdentity in
            let d = component.audioComponentDescription
            var identity = ExternalAUIdentity(type: d.componentType, subtype: d.componentSubType,
                                              manufacturer: d.componentManufacturer, name: component.name)
            let vendor = component.manufacturerName
            identity.vendor = vendor.isEmpty ? nil : vendor
            let version = component.versionString
            identity.version = version.isEmpty ? nil : version
            identity.isV3 = d.componentFlags & AudioComponentFlags.isV3AudioUnit.rawValue != 0
            #if os(macOS)
            identity.hasCustomView = component.hasCustomView
            #endif
            identity.unavailableReason = Self.unavailableReason(component)
            do {if try loadRecovery().isBlocked(identity.id) {identity.unavailableReason="Blocked after a failed/interrupted load. Use Allow Blocked Loads to retry."}}
            catch {identity.unavailableReason="The Audio Unit recovery journal could not be read. Preserve it and contact support."}
            #if os(macOS)
            identity.validated = component.passesAUVal
            #endif
            return identity
        }
        return ExternalAUCatalog.sorted(identities)
    }
    /// Hard reasons this listed component cannot be hosted here. Only a missing
    /// processor slice is treated as unavailable; auval status is reported but
    /// never blocks, because working plug-ins are often simply unvalidated.
    private static func unavailableReason(_ component: AVAudioUnitComponent) -> String? {
        #if os(macOS)
        let architectures = component.availableArchitectures
        guard !architectures.isEmpty else { return nil }
        #if arch(arm64)
        let current = NSNumber(value: 0x0100_000C) // CPU_TYPE_ARM64
        #elseif arch(x86_64)
        let current = NSNumber(value: 0x0100_0007) // CPU_TYPE_X86_64
        #else
        return nil
        #endif
        return architectures.contains(current) ? nil : "This Audio Unit has no build for this Mac's processor."
        #else
        return nil
        #endif
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
            var sound:ExternalSound
            do {sound=try importCompatibleEXS(compatible,sampleRoot:root)}
            catch {
                let temporary=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".aupreset")
                defer{try? FileManager.default.removeItem(at:temporary)}
                let program=try EXSNative.convert(compatible,sampleRoot:root,to:temporary)
                sound=try importPreset(temporary,sampleRoot:root);sound.nativeSampler=program
            }
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
        var nativeProgram:NativeSamplerProgram?
        if let metadata=state["StageKeys.NativeSampler"] as? Data {
            guard metadata.count<=2_000_000,let decoded=try? JSONDecoder().decode(NativeSamplerProgram.self,from:metadata),decoded.valid else{throw ExternalInstrumentError.unsupportedFormat}
            nativeProgram=decoded
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
            return ExternalSound(kind: .samplerPreset, name: url.deletingPathExtension().lastPathComponent, fileName: preset.lastPathComponent,nativeSampler:nativeProgram)
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
        guard var state = sampler.auAudioUnit.fullStateForDocument,
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
        sampler.auAudioUnit.fullStateForDocument = state
    }
    #if DEBUG
    func debugBuiltin(_ channel:Int)->AVAudioUnitEffect? {voices[channel]?.builtin}
    #endif
    func contains(_ channel: Int) -> Bool { voices[channel] != nil }
    func load(_ sound: ExternalSound, channel: Int, attackMinimum:Float=0, hostVelocityCurve:Int?=nil, completion: @escaping (Result<Void, Error>) -> Void) {
        precondition(Thread.isMainThread)
        guard (0..<16).contains(channel) else { completion(.failure(ExternalInstrumentError.invalidChannel)); return }
        let generation = UUID()
        generations[channel] = generation
        if sound.kind == .audioUnit {
            guard let component = sound.component, component.type == kAudioUnitType_MusicDevice else {
                completion(.failure(ExternalInstrumentError.invalidComponent)); return
            }
            #if os(iOS)
            if let reason=component.platformUnavailableReason(isMobile:true) {
                completion(.failure(NSError(domain:"StageKeysPluginPlatform",code:1,userInfo:[NSLocalizedDescriptionKey:reason])));return
            }
            #endif
            let recovery:PluginLoadRecovery
            do {recovery=try Self.loadRecovery();try recovery.begin(component.id)}
            catch {completion(.failure(error));return}
            var finished=false
            func finish(_ result:Result<Void,Error>,failed:Bool=false) {
                guard !finished else{return};finished=true
                do {try recovery.finish(component.id,failed:failed);completion(result)}
                catch {completion(.failure(error))}
            }
            DispatchQueue.main.asyncAfter(deadline:.now()+10) { [weak self] in
                guard !finished else{return}
                guard self?.generations[channel]==generation else{finish(.failure(ExternalInstrumentError.superseded));return}
                finish(.failure(NSError(domain:"StageKeysPluginRecovery",code:2,userInfo:[NSLocalizedDescriptionKey:"Audio Unit loading timed out after 10 seconds. It is blocked until you explicitly allow another attempt."])),failed:true)
            }
            #if os(macOS)
            let options:AudioComponentInstantiationOptions = component.isV3 == true ? .loadOutOfProcess:[]
            #else
            let options:AudioComponentInstantiationOptions = []
            #endif
            AVAudioUnit.instantiate(with: component.description, options: options) { [weak self] unit, error in
                DispatchQueue.main.async {
                    guard !finished else{return}
                    guard let self else {finish(.failure(ExternalInstrumentError.superseded));return}
                    guard self.generations[channel] == generation else {
                        finish(.failure(ExternalInstrumentError.superseded)); return
                    }
                    guard let unit, unit.auAudioUnit.scheduleMIDIEventBlock != nil else {
                        finish(.failure(error ?? ExternalInstrumentError.invalidComponent),failed:true); return
                    }
                    do { try self.install(unit, channel: channel); finish(.success(())) }
                    catch { finish(.failure(error),failed:true) }
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
                try SamplerRendering.configure(sampler,offline:engine.isInManualRenderingMode,resident:sound.nativeSampler != nil)
                if sound.kind == .soundBank {
                    try sampler.loadSoundBankInstrument(at: file, program: sound.program, bankMSB: sound.bankMSB, bankLSB: sound.bankLSB)
                } else if sound.kind == .samplerPreset {
                    try Self.verifySamples(file)
                    try install(sampler, channel: channel) { let document=try SamplerAttack.load(sampler,file:file,minimum:attackMinimum,curve:hostVelocityCurve);self.rememberSampler(sampler,document:document) }
                    voices[channel]?.nativePreset=file;voices[channel]?.attackMinimum=attackMinimum;voices[channel]?.hostVelocityCurve=hostVelocityCurve
                    if sound.nativeSampler != nil {
                        // MainStage starts with unity volume/expression. Keep any
                        // actual received values across instrument changes/reloads.
                        for controller in [7,11] where controllerValues[channel]?[controller]==nil {control(channel:channel,controller:UInt8(controller),value:127)}
                    }
                    completion(.success(()))
                    return
                } else { try loadSample(sampler, url: file) }
                try install(sampler, channel: channel)
                completion(.success(()))
            } catch { completion(.failure(error)) }
        }
    }
    /// Reject managed presets whose samples are missing or offline before the
    /// sampler is attached. AUSampler accepts an incomplete preset and can then
    /// play silence or a stale instrument, and resident playback cannot recover
    /// a file that disappeared after import. Only absolute paths and file URLs
    /// are checked here; other references stay with the sampler's own resolver.
    /// Runs on load, never on the audio render thread.
    private static func verifySamples(_ preset:URL)throws {
        guard let size=(try? preset.resourceValues(forKeys:[.fileSizeKey]))?.fileSize,size<=16_000_000,
              let data=try? Data(contentsOf:preset),
              let state=try? PropertyListSerialization.propertyList(from:data,options:[],format:nil) as? [String:Any],
              let references=state["file-references"] as? [String:String] else{return}
        for (_,reference) in references.sorted(by:{$0.key<$1.key}).prefix(4096) {
            let path:String
            if reference.hasPrefix("file://") {
                guard let url=URL(string:reference),url.isFileURL else{continue}
                path=url.path
            } else if reference.hasPrefix("/") {path=reference}
            else {continue}
            guard FileManager.default.fileExists(atPath:path) else {
                throw NSError(domain:"StageKeysSampler",code:1,userInfo:[NSLocalizedDescriptionKey:
                    "Missing sample: \(URL(fileURLWithPath:path).lastPathComponent). Import this sound again or reconnect its storage."])
            }
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
    // Reconnecting an AVAudioEngine graph can reinitialize AUSampler and clear
    // its instrument even when start() succeeds. Preserve document state (which
    // includes file references), not fullState's nonportable transient state.
    private final class SamplerHandle {weak var sampler:AVAudioUnitSampler?;init(_ sampler:AVAudioUnitSampler){self.sampler=sampler}}
    private var samplerHandles:[ObjectIdentifier:SamplerHandle] = [:]
    private var samplerDocuments:[ObjectIdentifier:[String:Any]] = [:]
    private func rememberSampler(_ sampler:AVAudioUnitSampler,document:[String:Any]?=nil) {
        let identity=ObjectIdentifier(sampler)
        if let document,document["StageKeys.NativeSampler"] != nil {
            samplerHandles[identity]=SamplerHandle(sampler);samplerDocuments[identity]=document;return
        }
        // AUSampler's serialized state can omit authored EXS modulation routes.
        // Preserve our exact loaded document across graph rebuilds. Tie it to
        // the live object, not just its address, which may later be reused.
        if samplerHandles[identity]?.sampler === sampler,samplerDocuments[identity]?["StageKeys.NativeSampler"] != nil {return}
        samplerHandles[identity]=SamplerHandle(sampler)
        if var state=sampler.auAudioUnit.fullStateForDocument,
           let refs=state["file-references"] as? [String:Any],!refs.isEmpty {
            // AUSampler omits default full keyboard ranges when serializing. On
            // reload, omitted ranges can be inferred from the sample filename
            // instead (e.g. Tone.wav becomes a single key). Make defaults explicit.
            if var instrument=state["Instrument"] as? [String:Any],var layers=instrument["Layers"] as? [[String:Any]] {
                for i in layers.indices {if var zones=layers[i]["Zones"] as? [[String:Any]] {
                    for j in zones.indices {for (key,value) in [("min key",0),("max key",127),("min vel",1),("max vel",127)] where zones[j][key]==nil {zones[j][key]=value}}
                    layers[i]["Zones"]=zones
                }}
                instrument["Layers"]=layers;state["Instrument"]=instrument
            }
            samplerDocuments[ObjectIdentifier(sampler)]=state
        }
    }
    private func samplerState() -> [(AVAudioUnitSampler,[String:Any])] {
        // Enumerate only owned samplers. AVAudioEngine.attachedNodes can create
        // the input singleton and trigger microphone access in a playback app.
        samplerHandles=samplerHandles.filter{$0.value.sampler?.engine === engine}
        let ids=Set(samplerHandles.keys)
        samplerDocuments=samplerDocuments.filter{ids.contains($0.key)}
        let samplers=samplerHandles.values.compactMap(\.sampler)
        return samplers.compactMap { sampler in
            rememberSampler(sampler)
            guard let state=samplerDocuments[ObjectIdentifier(sampler)] else{return nil}
            return (sampler,state)
        }
    }
    #if DEBUG
    private(set) var samplerRestorationCount = 0
    #endif
    private func restoreSamplers(_ states:[(AVAudioUnitSampler,[String:Any])]) throws {
        for (sampler,state) in states where sampler.engine === engine {
            // loadInstrument resolves document file references; assigning state
            // alone can retain metadata without repopulating offline sample data.
            let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".aupreset")
            defer{try? FileManager.default.removeItem(at:file)}
            try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:file)
            try sampler.loadInstrument(at:file)
            #if DEBUG
            samplerRestorationCount += 1
            #endif
        }
        // Instrument reloads reset AU controller state. Restore the held pedal
        // and filter/level CCs after every sampler in the graph has reloaded.
        for (channel,voice) in voices where voice.unit is AVAudioUnitSampler {
            for (controller,value) in (controllerValues[channel] ?? [:]).sorted(by:{$0.key<$1.key}) where controller<120 {
                (voice.unit as? AVAudioUnitSampler)?.sendController(UInt8(controller),withValue:UInt8(value),onChannel:0)
                voice.parallel.forEach{$0.control(UInt8(controller),UInt8(value))}
            }
        }
    }
    private struct GraphEdit {
        var mixers: [(AVAudioMixerNode, Float, Float)]
        var samplers: [(AVAudioUnitSampler, [String: Any])]
        var wasRunning: Bool
    }
    private var graphBatchDepth = 0
    private var pendingGraphEdit: GraphEdit?
    /// One lazy graph transaction per patch. Built-in-only updates never stop audio.
    func withGraphChanges(_ operation: () throws -> Void) throws {
        precondition(Thread.isMainThread)
        if graphBatchDepth > 0 { try operation(); return }
        graphBatchDepth = 1
        defer { graphBatchDepth = 0 }
        do { try operation() }
        catch { try? finishGraphChanges(); throw error }
        try finishGraphChanges()
    }
    private func finishGraphChanges() throws {
        guard var edit = pendingGraphEdit else { return }
        pendingGraphEdit = nil
        edit.samplers += samplerState().filter { candidate in !edit.samplers.contains(where: { $0.0 === candidate.0 }) }
        var failure: Error?
        do { try restoreSamplers(edit.samplers) } catch { failure = error }
        restoreMixers(edit.mixers)
        if edit.wasRunning {
            do { engine.prepare(); try engine.start() } catch { if failure == nil { failure = error } }
        }
        if let failure { throw failure }
    }
    private func editGraph(_ operation: () throws -> Void) throws {
        if graphBatchDepth == 0 {
            try withGraphChanges { try editGraph(operation) }
            return
        }
        if pendingGraphEdit == nil {
            pendingGraphEdit = GraphEdit(mixers: mixerState(), samplers: samplerState(), wasRunning: engine.isRunning)
            if engine.isRunning { engine.stop() }
        }
        try operation()
    }
    private func install(_ unit: AVAudioUnit, channel: Int, configure: (() throws -> Void)? = nil) throws {
        try editGraph {
            engine.attach(unit)
            do {
                try configure?()
                if let sampler = unit as? AVAudioUnitSampler { rememberSampler(sampler) }
            } catch { engine.detach(unit); throw error }
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
            let compressor=BuiltinEffectUnit.make()
            for node in [mixer as AVAudioNode, filter, eq, compressor] { engine.attach(node) }
            let processingFormat=AVAudioFormat(standardFormatWithSampleRate:engine.isInManualRenderingMode ? engine.manualRenderingFormat.sampleRate:48000,channels:2)!
            engine.connect(unit, to: filter, format: processingFormat)
            engine.connect(filter, to: eq, format: processingFormat)
            engine.connect(eq, to: compressor, format: processingFormat)
            let builtin=BuiltinEffectUnit.make();engine.attach(builtin)
            let voice = Voice(unit: unit, mixer: mixer, filter: filter, eq: eq, compressor: compressor,builtin:builtin)
            connectEffects(voice)
            engine.connect(mixer, to: engine.mainMixerNode, format: nil)
            voices[channel] = voice
        }
    }
    private func detach(_ channel: Int) {
        guard let old = voices.removeValue(forKey: channel) else { return }
        for node in [old.unit as AVAudioNode, old.filter, old.eq, old.compressor, old.mixer,old.builtin] + old.imported.map({$0 as AVAudioNode}) + old.parallelNodes + (old.audioGraph?.nodes ?? []) {
            engine.disconnectNodeOutput(node); engine.detach(node)
        }
    }
    func remove(_ channel: Int) throws {
        precondition(Thread.isMainThread)
        generations[channel] = UUID()
        // Cancel any pending load even when no voice is installed. Empty slots
        // do not change the graph and must not reload every resident sampler.
        guard voices[channel] != nil else { return }
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
        midi(channel, 0x90, note, UInt8(max(1, min(127, Int((velocity * 127).rounded())))))
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
    func initializeMainStageControllers(channel:Int) {
        for controller in [7,11] where controllerValues[channel]?[controller]==nil {
            control(channel:channel,controller:UInt8(controller),value:127)
        }
    }
    func control(channel: Int, controller: UInt8, value: UInt8) { precondition(Thread.isMainThread); guard controller < 128, value < 128 else { return };controllerValues[channel,default:[:]][Int(controller)]=Int(value);voices[channel]?.parallel.forEach{$0.control(controller,value)}; midi(channel, 0xB0, controller, value) }
    func sustain(channel: Int, on: Bool) { precondition(Thread.isMainThread);controllerValues[channel,default:[:]][64]=on ? 127:0; voices[channel]?.parallel.forEach{$0.control(64,on ? 127:0)};midi(channel, 0xB0, 64, on ? 127 : 0) }
    func volume(channel: Int, gain: Float, pan: Float) {
        precondition(Thread.isMainThread)
        voices[channel]?.mixer.outputVolume = max(0, min(4, gain))
        voices[channel]?.mixer.pan = max(-1, min(1, pan))
    }
    /// Audio processing for imported instruments. The host supplies the fader-
    /// interpolated cutoff; instrument envelopes remain the plug-in's own controls.
    func processing(channel: Int, gain: Float, cutoff: Float, resonance: Float,
                    eqEnabled: Bool, bands: [(frequency: Float, gain: Float, q: Float)],
                    compressorEnabled: Bool, threshold: Float, attack: Float, release: Float, makeup: Float,ratio:Float=4,inputGain:Float=0,mix:Float=1) {
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
        (voice.compressor.auAudioUnit as? BuiltinEffectUnit)?.configure(slot:0,kind:6,enabled:compressorEnabled,values:[inputGain,attack*1000,release*1000,ratio,threshold,mix,makeup],tempo:120)

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
    func panic(_ channel: Int? = nil,preserveEffectTails:Bool=false) {
        precondition(Thread.isMainThread)
        for index in channel.map({ [$0] }) ?? Array(voices.keys) {
            controllerValues[index,default:[:]][64]=0
            voices[index]?.parallel.forEach{$0.panic(preserveEffectTails:preserveEffectTails)}
            midi(index, 0xB0, 64, 0)
            for note in voices[index]?.pitches.values ?? Dictionary<Int, UInt8>().values { midi(index, 0x80, note, 0) }
            midi(index, 0xB0, 123, 0); if !preserveEffectTails {midi(index, 0xB0, 120, 0)}
            voices[index]?.pitches.removeAll()
            if !preserveEffectTails {
            voices[index]?.builtin.auAudioUnit.reset()
            voices[index]?.compressor.auAudioUnit.reset()
            voices[index]?.imported.forEach{$0.auAudioUnit.reset()}
            voices[index]?.audioGraph?.reset()
            }
        }
    }
    func unit(channel: Int) -> AVAudioUnit? { voices[channel]?.unit }
    func state(channel: Int) -> [String: Any]? { voices[channel]?.unit.auAudioUnit.fullStateForDocument }
    func restoreState(_ state: [String: Any], channel: Int) {
        precondition(Thread.isMainThread)
        voices[channel]?.unit.auAudioUnit.fullStateForDocument = state
    }
}
