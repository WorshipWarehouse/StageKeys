import Foundation
import AVFoundation
import AudioToolbox

/// Scalar evidence for the original operation and graph completion. Raw error
/// descriptions/paths are never retained in the support record.
struct AudioGraphFailure: Codable, Equatable {
    struct Cause: Codable, Equatable {
        let domain: String
        let code: Int
        init(_ error: Error) {
            let ns = error as NSError
            domain = [NSOSStatusErrorDomain, "com.apple.coreaudio.avfaudio", NSPOSIXErrorDomain,
                      NSCocoaErrorDomain].contains(ns.domain) ? ns.domain : "other"
            code = ns.code
        }
    }
    let id: UUID
    let generation: UInt64
    let edited: Bool
    let wasRunning: Bool
    let engineRunning: Bool
    let operation: Cause?
    let restoration: Cause?
    let restart: Cause?
    var rollbackSucceeded: Bool? = nil
    var rollback: Cause? = nil
}

extension ExternalAUIdentity {
    var description: AudioComponentDescription {
        AudioComponentDescription(componentType: type, componentSubType: subtype,
                                  componentManufacturer: manufacturer, componentFlags: 0, componentFlagsMask: 0)
    }
}

enum ExternalInstrumentError: LocalizedError {
    case unsupportedFormat, missingFile, invalidComponent, invalidChannel, superseded, unsupportedEffect, unavailableAudioUnit(String)
    var errorDescription: String? {
        switch self {
        case .unavailableAudioUnit(let reason): return reason
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
    private(set) var tempo: Float = 120
    var pitches:[Int:UInt8]=[:]
    var controllers:[Int:Int]=[:]
    init(_ plan:ImportedBranch){self.plan=plan}
    func configure(_ plan:ImportedBranch,tempo:Float) {
        self.plan=plan;self.tempo=tempo;output.pan=plan.pan;output.outputVolume=plan.enabled != false ? (plan.gain ?? 1):0
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
    // Two complete 16-slot request sets (15 performance slots plus Tonic).
    // Admission covers all rack instances in this process, including cancelled
    // requests whose backend callback has not returned yet.
    static let maximumPendingInstantiations = 32
    static let loadCapacityErrorDomain = "StageKeysPluginLoadCapacity"
    private static var pendingInstantiations = Set<UUID>()
    private static var recoveryStores:[String:PluginLoadRecovery]=[:]
    private static func loadRecovery()throws->PluginLoadRecovery {
        precondition(Thread.isMainThread)
        let base=ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"].map{URL(fileURLWithPath:$0)} ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("StageKeys")
        let url=base.appendingPathComponent("plugin-load-recovery.json")
        if let existing=recoveryStores[url.path]{return existing}
        let recovery=try PluginLoadRecovery(url:url);recoveryStores[url.path]=recovery;return recovery
    }
    static func allowBlockedLoads()throws {try loadRecovery().allowBlockedLoads()}
    static func allowBlockedLoad(_ id: String) throws { try loadRecovery().allowBlockedLoad(id) }
    static func blockedComponentIDs() throws -> Set<String> { try loadRecovery().blockedIDs() }
    private var catalogScopeDepth = 0
    private var catalogWasRead = false
    private var scopedCatalog: [ExternalAUIdentity]?
    /// Reuse one lazy registry observation during a synchronous user operation.
    /// Never retain it across asynchronous loading or the next interaction.
    func withInstrumentCatalog<T>(_ operation: () throws -> T) rethrows -> T {
        precondition(Thread.isMainThread)
        let outer = catalogScopeDepth == 0
        if outer { scopedCatalog = nil; catalogWasRead = false }
        catalogScopeDepth += 1
        defer {
            catalogScopeDepth -= 1
            if outer { scopedCatalog = nil; catalogWasRead = false }
        }
        return try operation()
    }
    private func instrumentCatalog() -> [ExternalAUIdentity]? {
        if catalogScopeDepth > 0 && catalogWasRead { return scopedCatalog }
        let result: [ExternalAUIdentity]?
        #if DEBUG
        if let supplied = debugInstrumentCatalog { result = supplied() }
        else if debugInstantiate != nil { result = nil }
        else { result = Self.instruments() }
        #else
        result = Self.instruments()
        #endif
        if catalogScopeDepth > 0 { scopedCatalog = result; catalogWasRead = true }
        return result
    }
    private let engine: AVAudioEngine
    private var controllerValues:[Int:[Int:Int]]=[:]
    private struct NoteIntent {
        let pitch: Int
        let velocity: Float
        let source: Int32?
        var released = false
    }
    private var noteIntents: [Int: [Int: NoteIntent]] = [:]
    let libraryURL: URL
    private struct Voice {
        var unit: AVAudioUnit
        var nativePreset:URL? = nil
        var attackMinimum:Float=0
        var hostVelocityCurve:Int?
        var mixer: AVAudioMixerNode
        /// Unity-gain tap point downstream of the fader/pan mixer. Taps on the
        /// fader mixer observe its input, before `outputVolume` is applied.
        var meterMixer: AVAudioMixerNode
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
    /// A replaced graph keeps its output connected long enough to render its
    /// effect tail. It receives no new input, and is detached only while the
    /// engine is already stopped for another graph transaction.
    private final class RetiredTail {
        let channel:Int
        let nodes:[AVAudioNode]
        let mixer:AVAudioMixerNode
        var muteWorkItem:DispatchWorkItem?
        var silent=false
        let expiresAt = ProcessInfo.processInfo.systemUptime + 20
        init(channel:Int,nodes:[AVAudioNode],mixer:AVAudioMixerNode) {
            self.channel=channel;self.nodes=nodes;self.mixer=mixer
        }
    }
    private var retiredTails:[RetiredTail]=[]
    private var tailPanicGenerations = Array(repeating: UInt64(0), count: 16)
    private let maxRetiredTails=2
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
                voice.parallel.forEach{$0.panic(preserveEffectTails:true)}
                for (controller,value) in controllerValues[channel] ?? [:] {parallel.forEach{$0.control(UInt8(controller),UInt8(value))}}
                if !voice.parallel.isEmpty,let mix=voice.parallelNodes.last as? AVAudioMixerNode,mix.engine === engine {
                    let tailMixer=AVAudioMixerNode();engine.attach(tailMixer)
                    engine.disconnectNodeOutput(mix)
                    engine.connect(mix,to:tailMixer,format:nil)
                    // Bypass the filter/compressor shared with the new branch
                    // set; their old tails continue through the shared built-in FX.
                    engine.connect(tailMixer,to:voice.mixer,format:nil)
                    enqueueRetiredTail(channel:channel,nodes:voice.parallelNodes+[tailMixer],mixer:tailMixer)
                } else {
                    for node in voice.parallelNodes.reversed(){engine.disconnectNodeOutput(node);engine.detach(node)}
                }
                engine.disconnectNodeOutput(voice.unit)
                if parallel.isEmpty {engine.connect(voice.unit,to:voice.filter,format:nil)}
                else {
                    let mix=AVAudioMixerNode();engine.attach(mix);nodes.append(mix)
                    for (bus,branch) in parallel.enumerated() {engine.connect(branch.output,to:mix,fromBus:0,toBus:AVAudioNodeBus(bus),format:voice.filter.inputFormat(forBus:0))}
                    engine.connect(mix,to:voice.filter,format:voice.filter.inputFormat(forBus:0))
                }
                voice.parallel=parallel;voice.parallelNodes=nodes;voice.parallelTopology=topology;voices[channel]=voice
                #if DEBUG
                try injectGraphFault(.graphConnected)
                #endif
            }
        }
        for (i,branch) in voice.parallel.enumerated(){branch.configure(branches![i],tempo:tempo)}
    }
    func prepareOfflineSamples()throws {
        for voice in voices.values {if let sampler=voice.unit as? AVAudioUnitSampler {try SamplerRendering.configure(sampler,offline:true)};for branch in voice.parallel {try branch.prepareOffline()}}
    }
    func releaseSource(_ source:Int32){
        for (channel, notes) in noteIntents {
            for (key, note) in notes where note.source == source { noteOff(channel: channel, key: key, forceRelease: true) }
        }
        for voice in voices.values {voice.parallel.forEach{$0.releaseSource(source)}}
    }
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
                let hadGraph=voice.audioGraph != nil
                engine.disconnectNodeOutput(voice.compressor)
                if let old=voice.audioGraph {retireGraph(old,channel:channel,destination:voice.mixer)}
                else if !voice.imported.isEmpty {retireImported(voice.imported,channel:channel,destination:voice.mixer)}
                // The old graph/imported chain now has no input. Keep its output
                // tail, and attach the new graph to the same downstream built-in FX.
                if hadGraph {for node in voice.imported where node.engine === engine {engine.disconnectNodeOutput(node);engine.detach(node)}}
                voice.imported=[];voice.audioGraph=graph
                connectEffects(voice);voices[channel]=voice
                #if DEBUG
                try injectGraphFault(.graphConnected)
                #endif
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
    private let soundMeters = SoundMeterBank()
    init(engine: AVAudioEngine, libraryURL: URL? = nil) throws {
        self.engine = engine
        let base=ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"].map{URL(fileURLWithPath:$0,isDirectory:true)} ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("StageKeys",isDirectory:true)
        self.libraryURL = libraryURL ?? base.appendingPathComponent("Imported Sounds",isDirectory:true)
        try FileManager.default.createDirectory(at: self.libraryURL, withIntermediateDirectories: true)
    }
    /// The optional taps live on a unity-gain mixer after the per-sound effects
    /// and fader/pan, before the shared reverb and master limiter. Enabling or
    /// disabling this never edits the graph and never allocates on the render
    /// thread.
    func setMeteringEnabled(_ enabled: Bool) {
        precondition(Thread.isMainThread)
        soundMeters.setEnabled(enabled)
    }
    func soundMeter(channel: Int) -> OutputMeter.Reading? {
        precondition(Thread.isMainThread)
        return soundMeters.reading(channel: channel)
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
    var debugPendingInstantiationCount: Int { Self.pendingInstantiations.count }
    var debugInstantiationTimeout: TimeInterval = 10
    var debugInstrumentCatalog: (() -> [ExternalAUIdentity])?
    var debugInstantiate: ((AudioComponentDescription, @escaping (AVAudioUnit?, Error?) -> Void) -> Void)?
    private(set) var debugInstantiationCallbacks = 0
    private(set) weak var debugLastCandidate: AVAudioUnit?
    func debugActiveNoteCount(_ channel: Int) -> Int { voices[channel]?.pitches.count ?? 0 }
    enum GraphFaultPoint { case candidateAttached, graphConnected, pluginStateApplied, restoreSamplers, restartEngine }
    var debugGraphFault: ((GraphFaultPoint) -> Error?)?
    private func injectGraphFault(_ point: GraphFaultPoint) throws {
        if let error = debugGraphFault?(point) { throw error }
    }
    #endif
    func contains(_ channel: Int) -> Bool { voices[channel] != nil }
    /// Read-only preparation for a proposed sound. All checks precede removal
    /// of the current voice; the actual loader still rechecks at installation.
    func validateSound(_ sound: ExternalSound, checkInstallation: Bool = true) throws {
        precondition(Thread.isMainThread)
        if sound.kind == .audioUnit {
            guard let component = sound.component, component.type == kAudioUnitType_MusicDevice else {
                throw ExternalInstrumentError.invalidComponent
            }
            if checkInstallation {
                guard let catalog = instrumentCatalog() else { return } // DEBUG callback fixtures only.
                #if os(iOS)
                let mobile = true
                #else
                let mobile = false
                #endif
                if let reason = ExternalAUCatalog.unavailableReason(for: component, installed: catalog, isMobile: mobile) {
                    throw ExternalInstrumentError.unavailableAudioUnit(reason)
                }
            }
            return // Catalog presence does not prove instantiation/state restoration.
        }
        guard let name = sound.fileName, name == URL(fileURLWithPath: name).lastPathComponent,
              !name.isEmpty else { throw ExternalInstrumentError.missingFile }
        let file = libraryURL.appendingPathComponent(name)
        guard Self.readableFile(file) else { throw ExternalInstrumentError.missingFile }
        if sound.kind == .samplerPreset { try Self.verifySamples(file) }
    }
    /// Browse-time companion to `validateSound`: report a missing managed file or
    /// missing samples without loading anything, so the library can offer repair
    /// before the user adds the sound. Audio Units keep their own availability
    /// reason; this never substitutes plugin state for content.
    func contentIssue(for sound: ExternalSound) -> LibraryContentIssue? {
        guard sound.kind != .audioUnit else { return nil }
        guard let name = sound.fileName, LibraryRepair.safeName(name) else { return .missingFile }
        return Self.contentIssue(in: libraryURL.appendingPathComponent(name), kind: sound.kind)
    }
    static func contentIssue(in file: URL, kind: ExternalSound.Kind) -> LibraryContentIssue? {
        guard kind != .audioUnit else { return nil }
        guard Self.readableFile(file) else { return .missingFile }
        if kind == .samplerPreset, (try? Self.verifySamples(file)) == nil { return .missingSamples }
        return nil
    }
    func load(_ sound: ExternalSound, channel: Int, attackMinimum:Float=0, hostVelocityCurve:Int?=nil, configureCandidate: (() throws -> Void)? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        precondition(Thread.isMainThread)
        guard (0..<16).contains(channel) else { completion(.failure(ExternalInstrumentError.invalidChannel)); return }
        if graphBatchDepth == 0 { lastGraphFailure = nil }
        do { try validateSound(sound) } catch { completion(.failure(error)); return }
        if sound.kind == .audioUnit && Self.pendingInstantiations.count >= Self.maximumPendingInstantiations {
            completion(.failure(NSError(domain: Self.loadCapacityErrorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Earlier Audio Unit loads are still finishing. Wait before retrying. If they never finish, save your work and restart StageKeys."])))
            return
        }
        let generation = UUID()
        generations[channel] = generation
        if sound.kind == .audioUnit {
            guard let component = sound.component, component.type == kAudioUnitType_MusicDevice else {
                completion(.failure(ExternalInstrumentError.invalidComponent)); return
            }
            let recovery:PluginLoadRecovery
            do {recovery=try Self.loadRecovery();try recovery.begin(component.id)}
            catch {completion(.failure(error));return}
            let ticket = UUID()
            Self.pendingInstantiations.insert(ticket)
            var finished=false
            func finish(_ result:Result<Void,Error>,failed:Bool=false) {
                guard !finished else{return};finished=true
                do {try recovery.finish(component.id,failed:failed);completion(result)}
                catch {completion(.failure(error))}
            }
            #if DEBUG
            let timeout = debugInstantiationTimeout.isFinite ? max(0.001, min(10, debugInstantiationTimeout)) : 10
            #else
            let timeout: TimeInterval = 10
            #endif
            DispatchQueue.main.asyncAfter(deadline:.now()+timeout) { [weak self] in
                guard !finished else{return}
                guard self?.generations[channel]==generation else{finish(.failure(ExternalInstrumentError.superseded));return}
                finish(.failure(NSError(domain:"StageKeysPluginRecovery",code:2,userInfo:[NSLocalizedDescriptionKey:"Audio Unit loading timed out after 10 seconds. It is blocked until you explicitly allow another attempt."])),failed:true)
            }
            #if os(macOS)
            let options:AudioComponentInstantiationOptions = component.isV3 == true ? .loadOutOfProcess:[]
            #else
            let options:AudioComponentInstantiationOptions = []
            #endif
            let instantiated: (AVAudioUnit?, Error?) -> Void = { [weak self] unit, error in
                DispatchQueue.main.async {
                    // A timeout/cancellation does not cancel Core Audio's work.
                    // Release admission only when its callback actually arrives,
                    // even if the host result has already been completed.
                    ExternalInstrumentRack.pendingInstantiations.remove(ticket)
                    guard !finished else{return}
                    guard let self else {finish(.failure(ExternalInstrumentError.superseded));return}
                    #if DEBUG
                    self.debugInstantiationCallbacks += 1
                    #endif
                    guard self.generations[channel] == generation else {
                        finish(.failure(ExternalInstrumentError.superseded)); return
                    }
                    guard let unit, unit.auAudioUnit.scheduleMIDIEventBlock != nil else {
                        finish(.failure(error ?? ExternalInstrumentError.invalidComponent),failed:true); return
                    }
                    do { try self.install(unit, channel: channel, ready: configureCandidate); finish(.success(())) }
                    catch ExternalInstrumentError.superseded { finish(.failure(ExternalInstrumentError.superseded)) }
                    catch { finish(.failure(error),failed:true) }
                }
            }
            #if DEBUG
            if let instantiate = debugInstantiate {
                instantiate(component.description, instantiated)
                return
            }
            #endif
            AVAudioUnit.instantiate(with: component.description, options: options, completionHandler: instantiated)
        } else {
            do {
                guard let name = sound.fileName, name == URL(fileURLWithPath: name).lastPathComponent else {
                    throw ExternalInstrumentError.missingFile
                }
                let file = libraryURL.appendingPathComponent(name)
                guard Self.readableFile(file) else { throw ExternalInstrumentError.missingFile }
                let sampler = AVAudioUnitSampler()
                // A single-file sample must be resident in memory. Left streaming, the sampler
                // emits ~250 ms of digital silence every ~640 ms once the note is held.
                try SamplerRendering.configure(sampler,offline:engine.isInManualRenderingMode,resident:sound.nativeSampler != nil || sound.kind == .sample)
                if sound.kind == .soundBank {
                    try sampler.loadSoundBankInstrument(at: file, program: sound.program, bankMSB: sound.bankMSB, bankLSB: sound.bankLSB)
                } else if sound.kind == .samplerPreset {
                    try Self.verifySamples(file)
                    try install(sampler, channel: channel, ready: configureCandidate) { let document=try SamplerAttack.load(sampler,file:file,minimum:attackMinimum,curve:hostVelocityCurve);self.rememberSampler(sampler,document:document) }
                    voices[channel]?.nativePreset=file;voices[channel]?.attackMinimum=attackMinimum;voices[channel]?.hostVelocityCurve=hostVelocityCurve
                    if sound.nativeSampler != nil {
                        // MainStage starts with unity volume/expression. Keep any
                        // actual received values across instrument changes/reloads.
                        for controller in [7,11] where controllerValues[channel]?[controller]==nil {control(channel:channel,controller:UInt8(controller),value:127)}
                    }
                    completion(.success(()))
                    return
                } else { try loadSample(sampler, url: file) }
                try install(sampler, channel: channel, ready: configureCandidate)
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
    private static func readableFile(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        return (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true &&
            FileManager.default.isReadableFile(atPath: resolved.path)
    }
    private static func verifySamples(_ preset:URL)throws {
        guard let size=(try? preset.resourceValues(forKeys:[.fileSizeKey]))?.fileSize,size<=16_000_000,
              let data=try? Data(contentsOf:preset),
              let state=try? PropertyListSerialization.propertyList(from:data,options:[],format:nil) as? [String:Any] else{return}
        try verifyReferences(state)
    }
    private static func verifyReferences(_ state: [String: Any]) throws {
        guard let references = state["file-references"] as? [String: String] else { return }
        var checked = Set<String>()
        for (_, reference) in references.sorted(by: { $0.key < $1.key }) {
            let file: URL
            if reference.hasPrefix("file://") {
                guard let url = URL(string: reference), url.isFileURL else { throw ExternalInstrumentError.unsupportedFormat }
                file = url
            } else if reference.hasPrefix("/") { file = URL(fileURLWithPath: reference) }
            else { continue } // Leave relative/opaque references with the sampler resolver.
            guard checked.insert(file.path).inserted else { continue }
            guard readableFile(file) else {
                throw NSError(domain: "StageKeysSampler", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "A sample is missing or unreadable. Reconnect its storage or import the sound again."])
            }
        }
    }
    private func prepareActiveSamplerResources() throws {
        let active = Set(activeSamplers().map(ObjectIdentifier.init))
        for (sampler, state) in samplerState() where active.contains(ObjectIdentifier(sampler)) {
            try Self.verifyReferences(state)
        }
    }
    private func mixerState() -> [(AVAudioMixerNode, Float, Float)] {
        var nodes = [engine.mainMixerNode]
        for voice in voices.values {
            nodes.append(voice.mixer)
            nodes.append(voice.meterMixer)
        }
        return nodes.map { ($0, $0.outputVolume, $0.pan) }
    }
    private func restoreMixers(_ state: [(AVAudioMixerNode, Float, Float)]) {
        for (node, gain, pan) in state where node.engine === engine {
            node.outputVolume = gain; node.pan = pan
        }
        // Mixer snapshots describe topology, not permission to revive a tail
        // that Panic or its deadline has already made permanently silent.
        let now = ProcessInfo.processInfo.systemUptime
        for tail in retiredTails where tail.silent || tail.expiresAt <= now {
            tail.silent = true; tail.mixer.outputVolume = 0
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
            rememberSampler(sampler, document: state)
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
    /// Enumerate our nodes only: querying engine.attachedNodes can instantiate
    /// an input singleton and request microphone access in this playback app.
    private func graphNodes() -> [AVAudioNode] {
        var nodes: [AVAudioNode] = []
        for voice in voices.values {
            nodes += [voice.unit, voice.filter, voice.eq, voice.compressor, voice.builtin, voice.mixer, voice.meterMixer]
            nodes += voice.imported
            nodes += voice.parallelNodes
            nodes += voice.audioGraph?.nodes ?? []
        }
        nodes += retiredTails.flatMap(\.nodes)
        var seen = Set<ObjectIdentifier>()
        return nodes.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }
    private struct Route {
        let node: AVAudioNode
        let bus: AVAudioNodeBus
        let points: [AVAudioConnectionPoint]
        let format: AVAudioFormat
    }
    private struct Rollback {
        let nodes: [AVAudioNode]
        let routes: [Route]
        let voices: [Int: Voice]
        let controllers: [Int: [Int: Int]]
        let notes: [Int: [Int: NoteIntent]]
        let tails: [RetiredTail]
        let tailSilence: [Bool]
        let tailPanicGenerations: [UInt64]
        let mixers: [(AVAudioMixerNode, Float, Float)]
        let effects: [(BuiltinEffectUnit, [BuiltinEffectUnit.Setting])]
        let branches: [(ImportedBranchVoice, ImportedBranch, Float)]
    }
    private func rollbackSnapshot() -> Rollback {
        let nodes = graphNodes()
        var routes: [Route] = []
        for node in nodes where node.engine === engine {
            for bus in 0..<node.numberOfOutputs {
                let points = engine.outputConnectionPoints(for: node, outputBus: bus)
                if !points.isEmpty { routes.append(Route(node: node, bus: bus, points: points, format: node.outputFormat(forBus: bus))) }
            }
        }
        var branches: [(ImportedBranchVoice, ImportedBranch, Float)] = []
        func capture(_ branch: ImportedBranchVoice) {
            branches.append((branch, branch.plan, branch.tempo))
            branch.children.forEach(capture)
        }
        voices.values.forEach { $0.parallel.forEach(capture) }
        return Rollback(nodes: nodes, routes: routes, voices: voices, controllers: controllerValues,
            notes: noteIntents, tails: retiredTails, tailSilence: retiredTails.map(\.silent), tailPanicGenerations: tailPanicGenerations,
            mixers: (nodes.compactMap { $0 as? AVAudioMixerNode } + [engine.mainMixerNode]).map { ($0, $0.outputVolume, $0.pan) },
            effects: nodes.compactMap { ($0 as? AVAudioUnit)?.auAudioUnit as? BuiltinEffectUnit }.map { ($0, $0.configurationSnapshot()) }, branches: branches)
    }
    private func restoreGraph(_ snapshot: Rollback, samplers: [(AVAudioUnitSampler, [String: Any])], states: [(AVAudioUnit, [String: Any])], wasRunning: Bool) throws {
        engine.stop()
        // A failed edit may have attached the bank to a candidate mixer that is
        // about to be discarded. Reconcile before detaching nodes: AVAudioEngine
        // refuses to remove a tap from a node that has already left the graph.
        soundMeters.detachAll()
        let oldIDs = Set(snapshot.nodes.map(ObjectIdentifier.init))
        let oldTailIDs = Set(snapshot.tails.map(ObjectIdentifier.init))
        for tail in retiredTails where !oldTailIDs.contains(ObjectIdentifier(tail)) { tail.muteWorkItem?.cancel() }
        let current = graphNodes()
        for node in current where node.engine === engine { engine.disconnectNodeOutput(node) }
        for node in current.reversed() where !oldIDs.contains(ObjectIdentifier(node)) && node.engine === engine { engine.detach(node) }
        for node in snapshot.nodes where node.engine == nil { engine.attach(node) }
        for route in snapshot.routes { engine.connect(route.node, to: route.points, fromBus: route.bus, format: route.format) }
        voices = snapshot.voices; controllerValues = snapshot.controllers; noteIntents = snapshot.notes
        retiredTails = snapshot.tails
        for (channel, voice) in snapshot.voices {
            soundMeters.attach(voice.meterMixer, channel: channel)
        }
        for (index, tail) in retiredTails.enumerated() {
            let newerPanic = tailPanicGenerations.indices.contains(tail.channel) &&
                tailPanicGenerations[tail.channel] != snapshot.tailPanicGenerations[tail.channel]
            tail.silent = tail.silent || snapshot.tailSilence[index] || newerPanic || tail.expiresAt <= ProcessInfo.processInfo.systemUptime
            scheduleTailExpiry(tail)
        }
        for (unit, state) in states.reversed() where oldIDs.contains(ObjectIdentifier(unit)) {
            unit.auAudioUnit.fullStateForDocument = state
        }
        restoreControls(snapshot)
        #if DEBUG
        try injectGraphFault(.restoreSamplers)
        #endif
        try restoreSamplers(samplers)
        restoreMixers(snapshot.mixers)
        replayNotes()
        if wasRunning {
            #if DEBUG
            try injectGraphFault(.restartEngine)
            #endif
            engine.prepare(); try engine.start()
        }
    }
    private func restoreControls(_ snapshot: Rollback) {
        for (branch, plan, tempo) in snapshot.branches { branch.configure(plan, tempo: tempo) }
        for (unit, settings) in snapshot.effects { unit.restoreConfiguration(settings) }
        restoreMixers(snapshot.mixers)
    }
    /// Reloaded samplers have lost their voices. Replay only intent still owned
    /// by the same unit; a successful replacement must not inherit old notes.
    private func replayNotes() {
        let saved = noteIntents
        for (channel, notes) in saved {
            voices[channel]?.pitches.removeAll()
            voices[channel]?.parallel.forEach { $0.panic() }
            midi(channel, 0xB0, 120, 0)
            for (controller, value) in controllerValues[channel] ?? [:] where controller < 120 {
                voices[channel]?.parallel.forEach { $0.control(UInt8(controller), UInt8(value)) }
                midi(channel, 0xB0, UInt8(controller), UInt8(value))
            }
            for (key, note) in notes.sorted(by: { $0.key < $1.key }) {
                noteOn(channel: channel, key: key, pitch: note.pitch, velocity: note.velocity, sourceID: note.source)
                if note.released { noteOff(channel: channel, key: key) }
            }
        }
    }
    private struct GraphEdit {
        let rollback: Rollback
        var mixers: [(AVAudioMixerNode, Float, Float)]
        var samplers: [(AVAudioUnitSampler, [String: Any])]
        var wasRunning: Bool
        var states: [(AVAudioUnit, [String: Any])] = []
    }
    private var graphBatchDepth = 0
    private(set) var graphGeneration: UInt64 = 0
    private var pendingGraphEdit: GraphEdit?
    private var preparedRollback: Rollback?
    private(set) var lastGraphFailure: AudioGraphFailure?
    private struct GraphFinish {
        let edited: Bool
        let wasRunning: Bool
        var restoration: Error?
        var restart: Error?
    }
    /// One lazy graph transaction per patch. Keep original and completion
    /// failures separate, and preserve the original thrown error's type.
    func withGraphChanges(capturingControls: Bool = false, _ operation: () throws -> Void) throws {
        precondition(Thread.isMainThread)
        if graphBatchDepth > 0 {
            if capturingControls && pendingGraphEdit == nil && preparedRollback == nil { preparedRollback = rollbackSnapshot() }
            try operation(); return
        }
        graphBatchDepth = 1
        lastGraphFailure = nil
        if capturingControls { preparedRollback = rollbackSnapshot() }
        defer { graphBatchDepth = 0; preparedRollback = nil }
        var operationError: Error?
        do { try operation() } catch { operationError = error }
        let edit = pendingGraphEdit
        let finish = finishGraphChanges()
        var rollbackSucceeded: Bool?
        var rollbackError: Error?
        if let edit, operationError != nil || finish.restoration != nil || finish.restart != nil {
            do {
                try restoreGraph(edit.rollback, samplers: edit.samplers, states: edit.states, wasRunning: edit.wasRunning)
                rollbackSucceeded = true
            } catch {
                rollbackSucceeded = false; rollbackError = error
                engine.stop()
            }
        }
        if operationError != nil, !finish.edited, let preparedRollback {
            restoreControls(preparedRollback)
            // Restoring a changed branch MIDI plan can reset its scheduler.
            // Rebuild owned note intent from resident voices without disk reload.
            replayNotes()
            rollbackSucceeded = true
        }
        if operationError != nil || finish.restoration != nil || finish.restart != nil {
            lastGraphFailure = AudioGraphFailure(id: UUID(), generation: graphGeneration,
                edited: finish.edited, wasRunning: finish.wasRunning, engineRunning: engine.isRunning,
                operation: operationError.map(AudioGraphFailure.Cause.init),
                restoration: finish.restoration.map(AudioGraphFailure.Cause.init),
                restart: finish.restart.map(AudioGraphFailure.Cause.init),
                rollbackSucceeded: rollbackSucceeded, rollback: rollbackError.map(AudioGraphFailure.Cause.init))
        }
        if let operationError { throw operationError }
        if let error = finish.restoration ?? finish.restart { throw error }
    }
    private func finishGraphChanges() -> GraphFinish {
        guard var edit = pendingGraphEdit else {
            return GraphFinish(edited: false, wasRunning: engine.isRunning)
        }
        pendingGraphEdit = nil
        // Retired graphs must not reload their samplers during a later patch
        // transaction. Their effects can still decay into the output without
        // delaying the newly playable instrument.
        let active=Set(activeSamplers().map{ObjectIdentifier($0)})
        edit.samplers=edit.samplers.filter{active.contains(ObjectIdentifier($0.0))}
        edit.samplers += samplerState().filter { candidate in !edit.samplers.contains(where: { $0.0 === candidate.0 }) }
        var outcome = GraphFinish(edited: true, wasRunning: edit.wasRunning)
        do {
            #if DEBUG
            try injectGraphFault(.restoreSamplers)
            #endif
            try restoreSamplers(edit.samplers)
        } catch { outcome.restoration = error }
        restoreMixers(edit.mixers)
        if outcome.restoration == nil { replayNotes() }
        // A partially restored graph must not resume as if every instrument was
        // ready. The controller/store expose an explicit manual recovery state.
        if edit.wasRunning && outcome.restoration == nil {
            do {
                #if DEBUG
                try injectGraphFault(.restartEngine)
                #endif
                engine.prepare(); try engine.start()
            } catch {
                outcome.restart = error
                engine.stop() // A throwing start must not leave a partial-running state.
            }
        }
        return outcome
    }
    private func editGraph(_ operation: () throws -> Void) throws {
        if graphBatchDepth == 0 {
            try withGraphChanges { try editGraph(operation) }
            return
        }
        if pendingGraphEdit == nil {
            try prepareActiveSamplerResources()
            graphGeneration &+= 1
            pendingGraphEdit = GraphEdit(rollback: preparedRollback ?? rollbackSnapshot(), mixers: mixerState(), samplers: samplerState(), wasRunning: engine.isRunning)
            if engine.isRunning { engine.stop() }
            purgeSilentRetiredTails()
        }
        try operation()
    }
    private func activeSamplers()->[AVAudioUnitSampler] {
        var result:[AVAudioUnitSampler]=[]
        func append(_ branch:ImportedBranchVoice) {
            if let sampler=branch.sampler {result.append(sampler)}
            for child in branch.children {append(child)}
        }
        for voice in voices.values {
            if let sampler=voice.unit as? AVAudioUnitSampler {result.append(sampler)}
            for branch in voice.parallel {append(branch)}
        }
        return result
    }
    private func enqueueRetiredTail(channel:Int,nodes:[AVAudioNode],mixer:AVAudioMixerNode) {
        precondition(Thread.isMainThread)
        precondition(graphBatchDepth > 0,"Tail retirement must run inside a graph transaction")
        var seen=Set<ObjectIdentifier>()
        let unique=nodes.filter{seen.insert(ObjectIdentifier($0)).inserted}
        let tail=RetiredTail(channel:channel,nodes:unique,mixer:mixer)
        retiredTails.append(tail)
        // Hard count bound: deliberately truncate the oldest tail if needed,
        // even if it is still audible. This is not a measured CPU/memory budget.
        while retiredTails.count>maxRetiredTails {
            detachRetiredTail(retiredTails.removeFirst())
        }
        scheduleTailExpiry(tail)
    }
    private func scheduleTailExpiry(_ tail: RetiredTail) {
        tail.muteWorkItem?.cancel()
        guard !tail.silent else { return }
        let work = DispatchWorkItem { [weak tail] in
            guard let tail else { return }
            tail.silent = true; tail.mixer.outputVolume = 0
        }
        tail.muteWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, tail.expiresAt - ProcessInfo.processInfo.systemUptime), execute: work)
    }
    private func detachRetiredTail(_ tail:RetiredTail) {
        tail.muteWorkItem?.cancel()
        tail.mixer.outputVolume=0
        for node in tail.nodes.reversed() where node.engine === engine {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
        }
    }
    private func purgeSilentRetiredTails() {
        let silent=retiredTails.filter(\.silent)
        retiredTails.removeAll{$0.silent}
        for tail in silent {detachRetiredTail(tail)}
    }
    /// Panic with preserved effects leaves the retired dry/effect graph ringing;
    /// explicit Panic must suppress it without waiting for the next graph edit.
    private func silenceRetiredTail(_ tail:RetiredTail) {
        tail.mixer.outputVolume=0;tail.silent=true
        for node in tail.nodes {if let effect=node as? AVAudioUnitEffect {effect.auAudioUnit.reset()}}
    }
    /// Keep a replaced imported rack's reverb alive through a dedicated tail
    /// mixer. Its input was disconnected first, so it only renders silence plus
    /// the existing effect state.
    private func retireGraph(_ graph:ImportedAudioGraph,channel:Int,destination:AVAudioNode) {
        guard graph.output.engine === engine else{return}
        let mixer=AVAudioMixerNode();engine.attach(mixer)
        engine.disconnectNodeOutput(graph.output)
        engine.connect(graph.output,to:mixer,format:nil)
        engine.connect(mixer,to:destination,format:nil)
        enqueueRetiredTail(channel:channel,nodes:graph.nodes+[mixer as AVAudioNode],mixer:mixer)
    }
    private func retireImported(_ units:[AVAudioUnitEffect],channel:Int,destination:AVAudioNode) {
        guard let last=units.last,last.engine === engine else{return}
        let mixer=AVAudioMixerNode();engine.attach(mixer)
        engine.disconnectNodeOutput(last)
        engine.connect(last,to:mixer,format:nil)
        engine.connect(mixer,to:destination,format:nil)
        enqueueRetiredTail(channel:channel,nodes:units.map{$0 as AVAudioNode}+[mixer as AVAudioNode],mixer:mixer)
    }
    private func install(_ unit: AVAudioUnit, channel: Int, ready: (() throws -> Void)? = nil, configure: (() throws -> Void)? = nil) throws {
        try editGraph {
            engine.attach(unit)
            #if DEBUG
            debugLastCandidate = unit
            #endif
            do {
                #if DEBUG
                try injectGraphFault(.candidateAttached)
                #endif
                try configure?()
                if let sampler = unit as? AVAudioUnitSampler { rememberSampler(sampler) }
            } catch { engine.detach(unit); throw error }
            retire(channel)
            let mixer = AVAudioMixerNode()
            let meterMixer = AVAudioMixerNode()
            let filter = AVAudioUnitEQ(numberOfBands: 1)
            filter.bands[0].filterType = .resonantLowPass
            filter.bands[0].bypass = true
            let eq = AVAudioUnitEQ(numberOfBands: 8)
            for (i, band) in eq.bands.enumerated() {
                band.filterType = i == 0 ? .highPass : i == 1 ? .lowShelf : i == 6 ? .highShelf : i == 7 ? .lowPass : .parametric
                band.bypass = i == 0 || i == 7
            }
            let compressor=BuiltinEffectUnit.make()
            for node in [mixer as AVAudioNode, meterMixer, filter, eq, compressor] { engine.attach(node) }
            let processingFormat=AVAudioFormat(standardFormatWithSampleRate:engine.isInManualRenderingMode ? engine.manualRenderingFormat.sampleRate:48000,channels:2)!
            engine.connect(unit, to: filter, format: processingFormat)
            engine.connect(filter, to: eq, format: processingFormat)
            engine.connect(eq, to: compressor, format: processingFormat)
            let builtin=BuiltinEffectUnit.make();engine.attach(builtin)
            let voice = Voice(unit: unit, mixer: mixer, meterMixer: meterMixer, filter: filter, eq: eq, compressor: compressor,builtin:builtin)
            connectEffects(voice)
            engine.connect(mixer, to: meterMixer, format: nil)
            engine.connect(meterMixer, to: engine.mainMixerNode, format: nil)
            voices[channel] = voice
            soundMeters.attach(meterMixer, channel: channel)
            try ready?()
        }
    }
    private func retire(_ channel: Int) {
        guard voices[channel] != nil else { return }
        soundMeters.detach(channel: channel)
        panic(channel,preserveEffectTails:true)
        guard let old=voices.removeValue(forKey:channel) else{return}
        var nodes:[AVAudioNode]=[old.unit,old.filter,old.eq,old.compressor,old.mixer,old.meterMixer,old.builtin]
        nodes += old.imported.map{$0 as AVAudioNode}
        nodes += old.parallelNodes
        nodes += old.audioGraph?.nodes ?? []
        enqueueRetiredTail(channel:channel,nodes:nodes,mixer:old.mixer)
    }
    /// Discard only rack-owned nodes after a failed performance, while stopped.
    /// Retained sampler documents may no longer resolve after storage loss;
    /// retry must build the selected patch without reloading abandoned voices.
    func resetForRecovery() {
        precondition(Thread.isMainThread && !engine.isRunning && graphBatchDepth == 0)
        for channel in 0..<16 { cancelPendingLoad(channel) }
        panic()
        let nodes = graphNodes()
        retiredTails.forEach { $0.muteWorkItem?.cancel() }
        soundMeters.detachAll()
        for node in nodes where node.engine === engine { engine.disconnectNodeOutput(node) }
        for node in nodes.reversed() where node.engine === engine { engine.detach(node) }
        voices.removeAll(); retiredTails.removeAll(); noteIntents.removeAll()
        samplerHandles.removeAll(); samplerDocuments.removeAll()
        graphGeneration &+= 1
    }
    /// Supersede an in-flight AU instantiation without removing a playing voice.
    func cancelPendingLoad(_ channel: Int) {
        precondition(Thread.isMainThread)
        generations[channel] = UUID()
    }
    func remove(_ channel: Int) throws {
        precondition(Thread.isMainThread)
        generations[channel] = UUID()
        // Cancel any pending load even when no voice is installed. Empty slots
        // do not change the graph and must not reload every resident sampler.
        guard voices[channel] != nil else { return }
        try editGraph { retire(channel) }
    }
    private func midi(_ channel: Int, _ status: UInt8, _ data1: UInt8, _ data2: UInt8, sampleTime: Int64? = nil) {
        guard let unit = voices[channel]?.unit else { return }
        // A future sample time is only handed to the block API; native-style
        // sendMIDIEvent has no timestamp and remains the immediate fallback.
        if let sampleTime, let block = unit.auAudioUnit.scheduleMIDIEventBlock {
            var bytes = [status, data1, data2]
            bytes.withUnsafeMutableBufferPointer { block(AUEventSampleTime(sampleTime), 0, 3, $0.baseAddress!) }
            return
        }
        if let instrument = unit as? AVAudioUnitMIDIInstrument {
            instrument.sendMIDIEvent(status, data1: data1, data2: data2)
            return
        }
        guard let block = unit.auAudioUnit.scheduleMIDIEventBlock else { return }
        var bytes = [status, data1, data2]
        bytes.withUnsafeMutableBufferPointer { block(AUEventSampleTimeImmediate, 0, 3, $0.baseAddress!) }
    }
    /// A hosted AU that accepts sample-timed MIDI and has no immediate parallel
    /// branches can receive lookahead-scheduled notes.
    func canSchedule(channel: Int) -> Bool {
        guard let voice = voices[channel], voice.parallel.isEmpty else { return false }
        return voice.unit.auAudioUnit.scheduleMIDIEventBlock != nil
    }
    func noteOn(channel: Int, key: Int, pitch: Int, velocity: Float,sourceID:Int32? = nil,sampleTime:Int64? = nil) {
        precondition(Thread.isMainThread)
        guard (0...127).contains(pitch), velocity.isFinite, voices[channel] != nil else { return }
        noteIntents[channel, default: [:]][key] = NoteIntent(pitch: pitch, velocity: velocity, source: sourceID)
        // Parallel imported branches run their own MIDI FX clocks and cannot
        // share this engine's sample anchor, so they keep immediate delivery.
        if let branches=voices[channel]?.parallel,!branches.isEmpty {branches.forEach{$0.noteOn(key,pitch,velocity,sourceID)};return}
        if let previous = voices[channel]?.pitches[key] { midi(channel, 0x80, previous, 0, sampleTime: sampleTime) }
        let note = UInt8(pitch)
        voices[channel]?.pitches[key] = note
        midi(channel, 0x90, note, UInt8(max(1, min(127, Int((velocity * 127).rounded())))), sampleTime: sampleTime)
    }
    func noteOff(channel: Int, key: Int, forceRelease: Bool = false, sampleTime: Int64? = nil) {
        precondition(Thread.isMainThread)
        if !forceRelease && (controllerValues[channel]?[64] ?? 0) >= 64 {
            noteIntents[channel]?[key]?.released = true
        } else { noteIntents[channel]?[key] = nil }
        if let branches=voices[channel]?.parallel,!branches.isEmpty {branches.forEach{$0.midi.noteOff(channel:0,key:key,force:forceRelease)};return}
        if forceRelease { control(channel: channel, controller: 64, value: 0) }
        if let note = voices[channel]?.pitches.removeValue(forKey: key) { midi(channel, 0x80, note, 0, sampleTime: sampleTime) }
    }
    func noteOff(key: Int) {
        precondition(Thread.isMainThread)
        for channel in Array(voices.keys) {
            noteOff(channel: channel, key: key)
        }
    }
    func initializeMainStageControllers(channel:Int) {
        for controller in [7,11] where controllerValues[channel]?[controller]==nil {
            control(channel:channel,controller:UInt8(controller),value:127)
        }
    }
    func control(channel: Int, controller: UInt8, value: UInt8) { precondition(Thread.isMainThread); guard controller < 128, value < 128 else { return };controllerValues[channel,default:[:]][Int(controller)]=Int(value);if controller == 64 && value < 64 {noteIntents[channel] = noteIntents[channel]?.filter { !$0.value.released }};if controller == 120 || controller == 123 {noteIntents[channel] = nil};voices[channel]?.parallel.forEach{$0.control(controller,value)}; midi(channel, 0xB0, controller, value) }
    func sustain(channel: Int, on: Bool) { control(channel: channel, controller: 64, value: on ? 127 : 0) }
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
        guard let unit = voices[channel]?.unit, let previous = unit.auAudioUnit.fullStateForDocument else {
            throw ExternalInstrumentError.unsupportedFormat
        }
        try editGraph {
            pendingGraphEdit?.states.append((unit, previous))
            panic(channel)
            restoreState(state, channel: channel)
            #if DEBUG
            try injectGraphFault(.pluginStateApplied)
            #endif
        }
    }
    func panic(_ channel: Int? = nil,preserveEffectTails:Bool=false) {
        precondition(Thread.isMainThread)
        if !preserveEffectTails {
            for index in channel.map({ [$0] }) ?? Array(tailPanicGenerations.indices) where tailPanicGenerations.indices.contains(index) {
                tailPanicGenerations[index] &+= 1
            }
            for tail in retiredTails where channel.map({$0 == tail.channel}) ?? true {silenceRetiredTail(tail)}
        }
        for index in channel.map({ [$0] }) ?? Array(voices.keys) {
            noteIntents[index] = nil
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
    #if DEBUG
    func debugNoteIntentCount(_ channel: Int) -> Int { noteIntents[channel]?.count ?? 0 }
    var debugOwnedNodeCount: Int { graphNodes().count }
    var debugRetiredTailCount:Int {retiredTails.count}
    var debugRetiredTailStates:[(channel:Int,silent:Bool,gain:Float)] {retiredTails.map{($0.channel,$0.silent,$0.mixer.outputVolume)}}
    func debugExpireRetiredTails() {for tail in retiredTails {silenceRetiredTail(tail)}}
    #endif
    func restoreState(_ state: [String: Any], channel: Int) {
        precondition(Thread.isMainThread)
        voices[channel]?.unit.auAudioUnit.fullStateForDocument = state
    }
}
