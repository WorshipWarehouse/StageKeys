import Foundation

/// Local, provider-independent proposal boundary for a later optional builder.
/// Data only: no paths, scripts, downloads, network calls or automatic session mutation.
struct PatchDraftPlan:Codable {
    struct Sound:Codable {
        var libraryID:String
        var gain:Float
        var pan:Float=0
        var low:Int=0
        var high:Int=127
        var effects:[AudioEffect]?
    }
    struct Preview {
        var patch:Patch?
        var missingSoundIDs:[String]
        var warnings:[String]
    }
    var schemaVersion=1
    var name:String
    var sounds:[Sound]
    func preview(library:[LibrarySound],available:(ExternalSound)->Bool)throws->Preview {
        guard schemaVersion==1,!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count<=200,
              (1...15).contains(sounds.count),Set(sounds.map(\.libraryID)).count==sounds.count else{throw SetlistError.invalid}
        var layers:[Layer]=[],missing:[String]=[],warnings:[String]=[]
        for proposal in sounds {
            guard !proposal.libraryID.isEmpty,proposal.libraryID.count<=256,
                  proposal.gain.isFinite,(0...1).contains(proposal.gain),proposal.pan.isFinite,(-1...1).contains(proposal.pan),
                  (0...127).contains(proposal.low),(proposal.low...127).contains(proposal.high),
                  proposal.effects.map({$0.count==3 && $0.allSatisfy{$0.validate()}}) ?? true else{throw SetlistError.invalid}
            let matches=library.filter{$0.id==proposal.libraryID}
            guard matches.count==1,let entry=matches.first else{missing.append(proposal.libraryID);continue}
            var layer:Layer
            if let saved=entry.layer {layer=saved}
            else if let sound=entry.sound {layer=Layer(name:entry.name,instrument:-1,gain:proposal.gain);layer.external=sound;layer.importedRack=sound.nativeSampler?.rack}
            else {missing.append(proposal.libraryID);continue}
            if let external=layer.external,!available(external){missing.append(proposal.libraryID);continue}
            guard layer.loaded,layer.midiDestinationID==nil else{missing.append(proposal.libraryID);continue}
            layer.id=UUID();layer.gain=proposal.gain;layer.pan=proposal.pan;layer.low=proposal.low;layer.high=proposal.high
            if let effects=proposal.effects {layer.effects=effects}
            layers.append(layer)
            warnings += entry.conversionNotes ?? []
        }
        guard missing.isEmpty else{return Preview(patch:nil,missingSoundIDs:missing,warnings:warnings)}
        if layers.reduce(Float(0),{$0+$1.gain})>1 {warnings.append("Layer gains sum above unity. Audition at a low master level and review output headroom before confirming.")}
        layers += (layers.count..<15).map{_ in Layer.empty()}
        let patch=Patch(name:name,layers:layers,snapshots:[])
        var check=Setlist();check.patches=[patch];try check.validate()
        return Preview(patch:patch,missingSoundIDs:[],warnings:warnings)
    }
}

struct ImportedDelay: Codable, Equatable {
    var left: Double
    var right: Double
    var leftSynced: Bool
    var rightSynced: Bool
    var pingPong: Bool = false
    struct Channel:Codable,Equatable {
        var feedback:Float
        var crossFeedback:Float
        var mix:Float
        var input:Int?
        var feedbackPolarity:Float?
        var crossPolarity:Float?
        var lowCut:Float=20
        var highCut:Float=20000
        var valid:Bool {(input.map{(0...4).contains($0)} ?? true) && (feedbackPolarity.map{$0 == -1 || $0 == 1} ?? true) && (crossPolarity.map{$0 == -1 || $0 == 1} ?? true) && feedback.isFinite && crossFeedback.isFinite && (0...0.95).contains(feedback) && (0...0.95).contains(crossFeedback) && feedback+crossFeedback<=0.95 && mix.isFinite && (0...1).contains(mix) && lowCut.isFinite && highCut.isFinite && (20...20000).contains(lowCut) && (lowCut...20000).contains(highCut)}
    }
    var leftChannel:Channel?
    var rightChannel:Channel?
    var lowCut: Float = 20
    var highCut: Float = 20000
    func validate() -> Bool {
        (leftChannel?.valid ?? true) && (rightChannel?.valid ?? true) && (leftChannel == nil) == (rightChannel == nil) && !(leftChannel != nil && pingPong) && left.isFinite && right.isFinite && (0.001...5.334).contains(left) && (0.001...5.334).contains(right) && lowCut.isFinite && highCut.isFinite && (20...20000).contains(lowCut) && (lowCut...20000).contains(highCut)
    }
    func seconds(_ value:Double,synced:Bool,tempo:Float)->Float {Float(min(16,max(0.001,synced ? value*60/Double(tempo) : value)))}
}
struct AudioEffect: Codable, Equatable {
    var kind = 0 // 0 bypass, 1 tone, 2 tremolo, 3 delay
    var amount: Float = 0.5
    var enabled = true
    var importedDelay: ImportedDelay?
    var delayPingPong: Bool?
    var syncBeats: Float?
    var parameters: [Float]?
    /// Explicitly retained through edits; absent on legacy imported reverbs.
    var reverbCore: String?
    var usesCreamCoat: Bool {
        guard kind == 13 else { return false }
        if let reverbCore { return reverbCore == "creamcoat" }
        // Upgrade only the previously reconstructed, untouched Felt Room profile.
        guard let p=parameters, p.count==9 || p.count==10 else{return false}
        let observed:[Float]=[0,18,0.33,776,2884,0,0,1,0.23]
        return zip(p.prefix(9),observed).enumerated().allSatisfy { i,pair in abs(pair.0-pair.1)<(i==6 ? 0.011:0.0001) } && (p.count==9 || p[9]==1)
    }
    static func factoryDefault(kind:Int)->AudioEffect {
        var effect=AudioEffect();effect.kind=kind;effect.parameters=AudioEffectCatalog.defaults(for:kind)
        if kind==13 || kind==15 {effect.reverbCore="dense-v1"}
        if kind==3 {effect.parameters![1]=0.75;effect.delayPingPong=true}
        return effect
    }
    var playbackDelay:ImportedDelay? {
        if let importedDelay {return importedDelay}
        guard kind==3,delayPingPong==true else{return nil}
        return ImportedDelay(left:Double(values[1]),right:Double(values[1]),leftSynced:true,rightSynced:true,pingPong:true,highCut:values[2])
    }
    var renderValues:[Float] { kind == 13 ? values+[reverbCore == "dense-v1" ? 2:usesCreamCoat ? 1:0]:kind == 15 ? values+[reverbCore == "dense-v1" ? 1:0]:values }
    var title: String { AudioEffectCatalog.names.indices.contains(kind) ? AudioEffectCatalog.names[kind] : "No Effect" }
    var values: [Float] {
        if let parameters { if kind == 15 && parameters.count == 10 {return parameters+[1]}; return (kind == 13 || kind == 10) && parameters.count == 9 ? parameters+[1]:parameters }
        var values = AudioEffectCatalog.defaults(for: kind)
        if kind == 1 { values[0] = min(20000,max(20,-48000 * log(1 - (0.004 + amount*amount*0.8)) / (2 * .pi))) }
        if kind == 2 { values[0] = amount }
        if kind == 3 { values[3] = amount }
        return values
    }
    func validate() -> Bool {
        guard reverbCore.map({(kind == 13 && ["creamcoat","legacy","dense-v1"].contains($0)) || (kind == 15 && ["legacy","dense-v1"].contains($0))}) ?? true else{return false}
        guard delayPingPong == nil || kind==3 else{return false}
        guard importedDelay.map({kind == 3 && $0.validate()}) ?? true else{return false}
        guard syncBeats.map({ $0.isFinite && (0.0625...4).contains($0) }) ?? true, (0...17).contains(kind), amount.isFinite, (0...1).contains(amount) else { return false }
        guard let parameters else { return true }
        guard (parameters.count == AudioEffectCatalog.defaults(for: kind).count || (kind == 13 || kind == 10) && parameters.count == 9 || kind == 15 && parameters.count == 10), parameters.allSatisfy(\.isFinite) else { return false }
        return AudioEffectCatalog.descriptors(for: kind).allSatisfy { ($0.minimum...$0.maximum).contains(values[$0.index]) }
    }
}
/// Rack controls retained independently of the three performance effect slots.
struct ImportedMacroBinding: Codable, Equatable {
    var branchPath:[Int]?
    /// Pairs of audio-rack index and branch index, after the instrument branch path.
    var audioPath:[Int]?
    var effect: Int
    var parameter: Int
    var minimum: Float
    var maximum: Float
    var logarithmic = false
}
struct ImportedMacro: Codable, Equatable, Identifiable {
    var index: Int
    var name: String
    var value: Float
    var bindings: [ImportedMacroBinding]
    var midiCC:Int?
    var midiChannel:Int?
    var id: Int { index }
}
struct ImportedBranch: Codable, Equatable {
    var name: String
    var sampleLayers: [Int]
    var rack: ImportedRack
    var midi: MIDIProgram?
    var midiEnabled: Bool?
    var controllerGate:SamplerControllerGate?
    var low = 0
    var high = 127
    var velocityLow = 1
    var velocityHigh = 127
    var pan: Float = 0
    var gain:Float?
    var enabled:Bool?
    var topology: String { sampleLayers.map(String.init).joined(separator:",")+"|"+rack.audioTopology+"["+(rack.branches ?? []).map(\.topology).joined(separator:";")+"]" }
}
struct ImportedAudioBranch: Codable, Equatable {
    var name:String
    var rack:ImportedRack
    var pan:Float = 0
    var enabled:Bool = true
}
struct ImportedAudioRack: Codable, Equatable {
    /// Insert before this serial effect index, preserving device order.
    var beforeEffect:Int
    var name:String
    var branches:[ImportedAudioBranch]
}
struct ImportedRack: Codable, Equatable {
    /// Archived host amplitude response, not a MIDI/sample-zone velocity remap.
    var mainStageUnityControllers:Bool?
    var mainStageAmplitudeVelocityCurve:Int?
    var audioRacks:[ImportedAudioRack]?
    var effectCount:Int {
        effects.filter{$0.kind != 0}.count + (branches ?? []).reduce(0){$0+$1.rack.effectCount} + (audioRacks ?? []).reduce(0){sum,stage in sum+stage.branches.reduce(0){$0+$1.rack.effectCount}}
    }
    var audioTopology:String {
        effects.map{"\($0.kind):\($0.playbackDelay != nil)"}.joined(separator:",") + (audioRacks ?? []).map{"@\($0.beforeEffect)["+$0.branches.map{$0.rack.audioTopology}.joined(separator:";")+"]"}.joined()
    }
    var branches: [ImportedBranch]?
    var translationVersion: Int?
    var effects: [AudioEffect] = []
    var macros: [ImportedMacro] = []
    private func processingSize(depth:Int=0)->Int {
        guard depth<12 else{return 257}
        var size=effects.count+1
        for branch in branches ?? [] {size += branch.rack.processingSize(depth:depth+1);if size>256{return size}}
        for stage in audioRacks ?? [] {for branch in stage.branches {size += branch.rack.processingSize(depth:depth+1);if size>256{return size}}}
        return size
    }
    func validate(depth:Int = 0) -> Bool {
        guard (mainStageAmplitudeVelocityCurve.map{(-20...20).contains($0)} ?? true),depth<12,(depth>0 || processingSize()<=256) else{return false}
        if let audioRacks {
            guard audioRacks.count<=12 else{return false}
            for stage in audioRacks {
                guard (0...effects.count).contains(stage.beforeEffect),stage.name.count<=200,!stage.branches.isEmpty,stage.branches.count<=16 else{return false}
                for branch in stage.branches {guard branch.name.count<=200,branch.pan.isFinite,(-1...1).contains(branch.pan),branch.rack.branches == nil,branch.rack.validate(depth:depth+1) else{return false}}
            }
        }
        if let branches {
            guard !branches.isEmpty,branches.count<=64 else{return false}
            let indices=branches.flatMap(\.sampleLayers)
            guard Set(indices).count==indices.count,indices.count<=64 else{return false}
            for branch in branches {
                guard branch.controllerGate?.valid ?? true else{return false}
                if let children=branch.rack.branches,Set(children.flatMap(\.sampleLayers)) != Set(branch.sampleLayers) {return false}
                guard branch.name.count<=200,!branch.sampleLayers.isEmpty,branch.sampleLayers.allSatisfy({(0..<64).contains($0)}),branch.rack.validate(depth:depth+1),branch.midi.map({$0==$0.validated}) ?? true,(0...127).contains(branch.low),(branch.low...127).contains(branch.high),(1...127).contains(branch.velocityLow),(branch.velocityLow...127).contains(branch.velocityHigh),branch.pan.isFinite,(-1...1).contains(branch.pan),branch.gain.map({$0.isFinite && (0...4).contains($0)}) ?? true else{return false}}
        }
        guard effects.count <= 12, effects.allSatisfy({$0.validate()}), macros.count <= 128,
              Set(macros.map(\.index)).count == macros.count else { return false }
        return macros.allSatisfy { m in
            (m.midiCC.map{(0...127).contains($0)} ?? true) && (m.midiChannel.map{(0...15).contains($0)} ?? true) && (0..<128).contains(m.index) && m.name.count <= 200 && m.value.isFinite && (0...127).contains(m.value) && m.bindings.count <= 128 && m.bindings.allSatisfy { b in
                guard let rack=targetRack(b.branchPath ?? [],audioPath:b.audioPath ?? []),rack.effects.indices.contains(b.effect), b.minimum.isFinite, b.maximum.isFinite,
                      let p = AudioEffectCatalog.descriptors(for:rack.effects[b.effect].kind).first(where:{$0.index == b.parameter}) else { return false }
                return (p.minimum...p.maximum).contains(b.minimum) && (p.minimum...p.maximum).contains(b.maximum) && (!b.logarithmic || (b.minimum > 0 && b.maximum > 0))
            }
        }
    }
    mutating func applyMIDI(controller:Int,value:Float,channel:Int)->Bool {
        let matches=macros.filter{$0.midiCC==controller && ($0.midiChannel==nil || $0.midiChannel==channel)}.map(\.index)
        for index in matches {setMacro(index,value:value)}
        var changed = !matches.isEmpty
        if branches != nil {for i in branches!.indices {if branches![i].rack.applyMIDI(controller:controller,value:value,channel:channel){changed=true}}}
        if audioRacks != nil {for stage in audioRacks!.indices {for branch in audioRacks![stage].branches.indices {if audioRacks![stage].branches[branch].rack.applyMIDI(controller:controller,value:value,channel:channel){changed=true}}}}
        return changed
    }
    mutating func setMacro(_ index: Int, value: Float) {
        guard let i = macros.firstIndex(where:{$0.index == index}), value.isFinite else { return }
        macros[i].value = max(0,min(127,value))
        let t = macros[i].value / 127
        for binding in macros[i].bindings {apply(binding,path:binding.branchPath ?? [],audioPath:binding.audioPath ?? [],fraction:t)}
    }
    private func targetRack(_ path:[Int],audioPath:[Int])->ImportedRack? {
        var rack=self
        for index in path {guard let children=rack.branches,children.indices.contains(index) else{return nil};rack=children[index].rack}
        guard audioPath.count % 2 == 0 else{return nil}
        for offset in stride(from:0,to:audioPath.count,by:2) {let stage=audioPath[offset],branch=audioPath[offset+1];guard let stages=rack.audioRacks,stages.indices.contains(stage),stages[stage].branches.indices.contains(branch) else{return nil};rack=stages[stage].branches[branch].rack}
        return rack
    }
    private mutating func apply(_ binding:ImportedMacroBinding,path:[Int],audioPath:[Int],fraction:Float){
        if let index=path.first {guard branches?.indices.contains(index)==true else{return};branches![index].rack.apply(binding,path:Array(path.dropFirst()),audioPath:audioPath,fraction:fraction);return}
        if !audioPath.isEmpty {
            guard audioPath.count>=2,let stages=audioRacks,stages.indices.contains(audioPath[0]),stages[audioPath[0]].branches.indices.contains(audioPath[1]) else{return}
            audioRacks![audioPath[0]].branches[audioPath[1]].rack.apply(binding,path:[],audioPath:Array(audioPath.dropFirst(2)),fraction:fraction);return
        }
        guard effects.indices.contains(binding.effect) else{return}
        var values=effects[binding.effect].values;guard values.indices.contains(binding.parameter) else{return}
        values[binding.parameter]=binding.logarithmic ? exp(log(binding.minimum)+(log(binding.maximum)-log(binding.minimum))*fraction):binding.minimum+(binding.maximum-binding.minimum)*fraction
        effects[binding.effect].parameters=values

    }
}
struct Layer: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var instrument: Int // -1 is an empty module
    var gain: Float
    var muted = false
    var low = 0
    var high = 127
    var octave = 0
    var transpose: Int?
    var effectiveTranspose: Int { transpose ?? octave * 12 }
    var pan: Float = 0
    var blockSustain = false
    var octaveEffect = false
    var effects = [AudioEffect(), AudioEffect(), AudioEffect()]
    var channelSettings = ChannelSettings()
    var samplerAttackMinimum:Float {
        if let explicit=channelSettings.samplerAttackMinimum {return explicit}
        // Preserve the authored attack. The former Steinway smoothing masked a
        // disk-streaming fault and added noticeable onset latency.
        return 0
    }
    var external: ExternalSound?
    var importedRack: ImportedRack?
    var pluginState: Data?
    var midiEffectEnabled = true
    var midiProgram: MIDIProgram?
    var midiDestinationID: Int32?
    var midiOutputChannel = 0
    var loaded: Bool { external != nil || midiDestinationID != nil }
    static func empty() -> Layer { Layer(name: "Add Sound", instrument: -1, gain: 0) }
    enum CodingKeys: String, CodingKey { case id,name,instrument,gain,muted,low,high,octave,transpose,pan,blockSustain,octaveEffect,effects,channelSettings,external,importedRack,pluginState,midiEffectEnabled,midiProgram,midiDestinationID,midiOutputChannel }
    init(name: String, instrument: Int, gain: Float) { self.name = name; self.instrument = instrument; self.gain = gain; if instrument != 1 { channelSettings.attack = 0.006; channelSettings.release = 0.3 } }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        instrument = try c.decode(Int.self, forKey: .instrument); gain = try c.decode(Float.self, forKey: .gain)
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        low = try c.decodeIfPresent(Int.self, forKey: .low) ?? 0; high = try c.decodeIfPresent(Int.self, forKey: .high) ?? 127
        octave = try c.decodeIfPresent(Int.self, forKey: .octave) ?? 0
        transpose = try c.decodeIfPresent(Int.self, forKey: .transpose)
        pan = try c.decodeIfPresent(Float.self, forKey: .pan) ?? 0
        blockSustain = try c.decodeIfPresent(Bool.self, forKey: .blockSustain) ?? false
        octaveEffect = try c.decodeIfPresent(Bool.self, forKey: .octaveEffect) ?? false
        effects = try c.decodeIfPresent([AudioEffect].self, forKey: .effects) ?? [AudioEffect(),AudioEffect(),AudioEffect()]
        channelSettings = try c.decodeIfPresent(ChannelSettings.self, forKey: .channelSettings) ?? ChannelSettings()
        external = try c.decodeIfPresent(ExternalSound.self, forKey: .external)
        importedRack = try c.decodeIfPresent(ImportedRack.self, forKey: .importedRack)
        pluginState = try c.decodeIfPresent(Data.self, forKey: .pluginState)
        midiEffectEnabled = try c.decodeIfPresent(Bool.self, forKey: .midiEffectEnabled) ?? true
        midiProgram = try c.decodeIfPresent(MIDIProgram.self, forKey: .midiProgram)
        midiDestinationID = try c.decodeIfPresent(Int32.self, forKey: .midiDestinationID)
        midiOutputChannel = try c.decodeIfPresent(Int.self, forKey: .midiOutputChannel) ?? 0
    }
}
struct SnapshotSoundState: Codable {
    var importedRack: ImportedRack?
    var effects: [AudioEffect]
    var midiProgram: MIDIProgram?
    var midiEffectEnabled: Bool
    var pan: Float
    /// Serialized Audio Unit document state, so a scene recalls the plug-in
    /// exactly as captured. Absent in older setlists and for non-AU sounds.
    var pluginState: Data?
    init(_ layer: Layer) { importedRack=layer.importedRack; effects=layer.effects; midiProgram=layer.midiProgram; midiEffectEnabled=layer.midiEffectEnabled; pan=layer.pan; pluginState=layer.pluginState }
}
struct Snapshot: Codable, Identifiable {
    /// Nil in legacy sessions means a populated snapshot. Empty slots keep their index.
    var emptySlot: Bool?
    var isEmptySlot: Bool { emptySlot == true }
    var id = UUID()
    var name: String
    var gains: [Float]
    var sounds: [SnapshotSoundState]?
    var modulation: Float?
    var tonicTimbre:Int?
    var tonicRoot: Int?
    var tonicEnabled: Bool?
    var tonicLevel: Float?
    var tonicBrightness: Float?
    var tonicShimmer: Float?
    var note: String?
    var alignment: Int?
    var seconds: Float?
    var beats: Float?
    var noteText: String { note ?? "" }
}
struct TonicPatchState: Codable, Equatable {
    var enabled:Bool
    var root:Int
    var timbre:Int
    var sound:ExternalSound?
    var velocitySelector:Bool
    var gain:Float
    var brightness:Float
    var shimmer:Float
    var valid:Bool {(0..<12).contains(root) && (0..<12).contains(timbre) && [gain,brightness,shimmer].allSatisfy{$0.isFinite && (0...1).contains($0)} && (sound == nil || sound?.kind == .samplerPreset)}
}
struct Patch: Codable, Identifiable {
    var id = UUID()
    var name: String
    var tempo: Double = 72
    var transpose = 0
    var playIn = 0
    var hearIn = 0
    var layers: [Layer]
    var snapshots: [Snapshot] = []
    var visualMode = 0 // 0 unchanged, 1 effects, 2 notes
    var volumeDB: Float = 0
    var programChangeEnabled: Bool?
    var programChangeNumber: Int?
    var tonicState:TonicPatchState?
    var silencePrevious = false
    var conversionNotes:[String]?
    enum CodingKeys: String, CodingKey { case id,name,tempo,transpose,playIn,hearIn,layers,snapshots,visualMode,silencePrevious,volumeDB,programChangeEnabled,programChangeNumber,tonicState,conversionNotes }
    init(name: String, layers: [Layer], snapshots: [Snapshot]) { self.name = name; self.layers = layers; self.snapshots = snapshots }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        tempo = try c.decodeIfPresent(Double.self, forKey: .tempo) ?? 72
        transpose = try c.decodeIfPresent(Int.self, forKey: .transpose) ?? 0
        playIn = try c.decodeIfPresent(Int.self, forKey: .playIn) ?? 0
        hearIn = try c.decodeIfPresent(Int.self, forKey: .hearIn) ?? ((transpose % 12 + 12) % 12)
        layers = try c.decode([Layer].self, forKey: .layers); snapshots = try c.decode([Snapshot].self, forKey: .snapshots)
        visualMode = try c.decodeIfPresent(Int.self, forKey: .visualMode) ?? 0
        volumeDB = try c.decodeIfPresent(Float.self,forKey:.volumeDB) ?? 0
        programChangeEnabled = try c.decodeIfPresent(Bool.self,forKey:.programChangeEnabled)
        programChangeNumber = try c.decodeIfPresent(Int.self,forKey:.programChangeNumber)
        tonicState = try c.decodeIfPresent(TonicPatchState.self,forKey:.tonicState)
        silencePrevious = try c.decodeIfPresent(Bool.self, forKey: .silencePrevious) ?? false
        conversionNotes = try c.decodeIfPresent([String].self,forKey:.conversionNotes)
    }
    static func make(_ name:String = "New Patch") -> Patch {
        var patch=Patch(name:name,layers:(0..<15).map{_ in Layer.empty()},
                        snapshots:(0..<5).map{Snapshot(emptySlot:true,name:"Snapshot \($0+1)",gains:Array(repeating:0,count:15))})
        patch.programChangeEnabled=false
        return patch
    }
    func duplicate() -> Patch {
        var p = self; p.id = UUID(); p.name += " Copy"
        p.layers = layers.map { var l = $0; l.id = UUID(); return l }
        p.snapshots = snapshots.map { var s = $0; s.id = UUID(); return s }
        return p
    }
}
struct Setlist: Codable {
    var version = 4
    var name = "My Setlist"
    var patches = [Patch.make()]
    var assignments: [Int: Int] = [:]
    var controlAssignments: [Int:MIDIControlTarget]?
    func upgraded() throws -> Setlist {
        try validate()
        var s = self
        for i in s.patches.indices {
            let count = s.patches[i].layers.count
            s.patches[i].layers += (count..<15).map { _ in Layer.empty() }
            for j in s.patches[i].snapshots.indices {
                s.patches[i].snapshots[j].gains += Array(repeating:0,count:15-count)
                if s.patches[i].snapshots[j].sounds != nil { s.patches[i].snapshots[j].sounds! += s.patches[i].layers.suffix(15-count).map(SnapshotSoundState.init) }
            }
        }
        s.version = 4; return s
    }
    func validate() throws {
        guard (1...4).contains(version), !patches.isEmpty, patches.count <= 128, name.count <= 200 else { throw SetlistError.invalid }
        guard Set(patches.map(\.id)).count == patches.count else { throw SetlistError.invalid }
        for p in patches {
            guard p.conversionNotes.map({$0.count<=128 && $0.allSatisfy{$0.count<=2000}}) ?? true else {throw SetlistError.invalid}
            guard p.tonicState?.valid ?? true else{throw SetlistError.invalid}
            guard p.volumeDB.isFinite,(-24...12).contains(p.volumeDB),p.programChangeNumber == nil || (0...127).contains(p.programChangeNumber!), !p.name.isEmpty, p.name.count <= 200, p.tempo.isFinite, (20...300).contains(p.tempo), (-24...24).contains(p.transpose), (0...11).contains(p.playIn), (0...11).contains(p.hearIn), (1...15).contains(p.layers.count), p.snapshots.count <= 16, (0...2).contains(p.visualMode), Set(p.layers.map(\.id)).count == p.layers.count, Set(p.snapshots.map(\.id)).count == p.snapshots.count else { throw SetlistError.invalid }
            for l in p.layers {
                if let m = l.midiProgram { guard m == m.validated else { throw SetlistError.invalid } }
                if let e = l.external {
                    guard e.nativeSampler.map({$0.valid}) ?? true else{throw SetlistError.invalid}
                    guard e.name.count <= 200, e.program < 128, e.bankMSB < 128, e.bankLSB < 128 else { throw SetlistError.invalid }
                    if e.kind == .audioUnit { guard e.component?.type == 0x61756d75, (e.component?.name.count ?? 201) <= 200 else { throw SetlistError.invalid } }
                    else { guard let f = e.fileName, f == URL(fileURLWithPath: f).lastPathComponent, !f.isEmpty, f.count <= 200 else { throw SetlistError.invalid } }
                }
                guard l.importedRack?.validate() ?? true else { throw SetlistError.invalid }
                guard l.channelSettings.validate(), (0...15).contains(l.midiOutputChannel), (l.pluginState?.count ?? 0) <= 2_000_000, (-1...2).contains(l.instrument), l.gain.isFinite, (0...1).contains(l.gain), (0...127).contains(l.low), (l.low...127).contains(l.high), (-2...2).contains(l.octave), (-48...48).contains(l.effectiveTranspose), l.pan.isFinite, (-1...1).contains(l.pan), l.name.count <= 200, l.effects.count == 3, l.effects.allSatisfy({ $0.validate() }) else { throw SetlistError.invalid }
            }
            for s in p.snapshots {
                if let states = s.sounds { guard states.count == p.layers.count, states.allSatisfy({ ($0.importedRack?.validate() ?? true) && $0.effects.count == 3 && $0.effects.allSatisfy({ $0.validate() }) && $0.pan.isFinite && (-1...1).contains($0.pan) && ($0.midiProgram.map { $0 == $0.validated } ?? true) && ($0.pluginState?.count ?? 0) <= 2_000_000 }) else { throw SetlistError.invalid } }
                guard [s.modulation,s.tonicLevel,s.tonicBrightness,s.tonicShimmer].allSatisfy({ $0.map { $0.isFinite && (0...1).contains($0) } ?? true }), s.tonicRoot.map({ (0...11).contains($0) }) ?? true, s.tonicTimbre.map({(0..<12).contains($0)}) ?? true else { throw SetlistError.invalid }
                guard s.name.count <= 200, (s.note?.count ?? 0) <= 10_000, (0...2).contains(s.alignment ?? 0), s.gains.count == p.layers.count, s.gains.allSatisfy({ $0.isFinite && (0...1).contains($0) }), s.seconds.map({ $0.isFinite && (0...30).contains($0) }) ?? true, s.beats.map({ $0.isFinite && (0.25...32).contains($0) }) ?? true else { throw SetlistError.invalid }
            }
        }
        if let controls=controlAssignments { guard controls.count <= 128, controls.allSatisfy({ (0...127).contains($0.key) && !MIDIControlTarget.reservedCCs.contains($0.key) && $0.value.valid && assignments[$0.key] == nil }) else { throw SetlistError.invalid } }
        guard assignments.allSatisfy({ (0...127).contains($0.key) && (0...14).contains($0.value) }) else { throw SetlistError.invalid }
    }
}
enum SetlistError: LocalizedError {
    case invalid
    var errorDescription: String? { "This setlist has unsupported or invalid settings." }
}

struct EffectPreset: Codable, Equatable, Identifiable {
    var id=UUID()
    var name:String
    var effect:AudioEffect
    func validate()->Bool { !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && name.count<=80 && effect.kind>0 && effect.validate() }
}
enum EffectPresetArchive {
    static func load(_ url:URL)->[EffectPreset] {
        guard let data=try? Data(contentsOf:url),let presets=try? JSONDecoder().decode([EffectPreset].self,from:data),presets.count<=128,presets.allSatisfy({$0.validate()}),Set(presets.map(\.id)).count==presets.count else{return []}
        return presets
    }
    static func save(_ presets:[EffectPreset],to url:URL)throws {
        guard presets.count<=128,presets.allSatisfy({$0.validate()}),Set(presets.map(\.id)).count==presets.count else{throw CocoaError(.fileWriteInvalidFileName)}
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(presets).write(to:url,options:.atomic)
    }
}
