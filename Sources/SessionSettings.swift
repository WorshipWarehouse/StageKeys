import Foundation
/// Persisted metronome controls. The engine owns scheduling; this type validates
/// every value before launch so an edited `settings.json` cannot change bounds.
struct MetronomeSettings: Codable, Equatable {
    static let presets = ["Click", "Woodblock"]
    static let subdivisionLabels = ["Beats", "Eighths", "Triplets", "Sixteenths"]
    /// The engine caps the click at this peak amplitude before output headroom.
    static let peakAmplitude: Float = 0.2
    var visible = true
    var preset = 0
    var level: Float = 0.6
    var beatVelocity: Float = 0.7
    var downbeatEnabled = true
    var downbeatVelocity: Float = 1
    var beatsPerBar = 4
    var accentEvery = 0
    var subdivision = 1
    var followsMaster = true
    enum CodingKeys: String, CodingKey { case visible,preset,level,beatVelocity,downbeatEnabled,downbeatVelocity,beatsPerBar,accentEvery,subdivision,followsMaster }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        preset = try c.decodeIfPresent(Int.self, forKey: .preset) ?? 0
        level = try c.decodeIfPresent(Float.self, forKey: .level) ?? 0.6
        beatVelocity = try c.decodeIfPresent(Float.self, forKey: .beatVelocity) ?? 0.7
        downbeatEnabled = try c.decodeIfPresent(Bool.self, forKey: .downbeatEnabled) ?? true
        downbeatVelocity = try c.decodeIfPresent(Float.self, forKey: .downbeatVelocity) ?? 1
        beatsPerBar = try c.decodeIfPresent(Int.self, forKey: .beatsPerBar) ?? 4
        accentEvery = try c.decodeIfPresent(Int.self, forKey: .accentEvery) ?? 0
        subdivision = try c.decodeIfPresent(Int.self, forKey: .subdivision) ?? 1
        followsMaster = try c.decodeIfPresent(Bool.self, forKey: .followsMaster) ?? true
    }
    func validate() -> Bool {
        MetronomeSettings.presets.indices.contains(preset) && level.isFinite && (0...1).contains(level) && beatVelocity.isFinite && (0...1).contains(beatVelocity) && downbeatVelocity.isFinite && (0...1).contains(downbeatVelocity) && (1...16).contains(beatsPerBar) && (0...16).contains(accentEvery) && (1...4).contains(subdivision)
    }
    /// Nil means silent. The value is an engine peak, not a measured output level.
    var levelDBFS: Float? { level > 0 ? Float(20 * log10(Double(max(0.0001, level * MetronomeSettings.peakAmplitude)))) : nil }
    var beatVelocityLabel: String { "\(Int(beatVelocity * 127))" }
    var downbeatVelocityLabel: String { "\(Int(downbeatVelocity * 127))" }
}
struct SessionSettings: Codable {
    var selectedPatchID: UUID?
    var activeSnapshotID: UUID?
    var notesMode: Bool?
    var modWheel: Float?
    var master: Float = 0.7
    var reverb: Float = 22
    var transition: Float = 1.5
    var midiChannel = -1
    var primarySourceID: Int32?
    var secondarySourceID: Int32?
    var secondaryChannel: Int?
    var velocityMinimum: Int?
    var velocityMaximum: Int?
    var sourceNames: [Int32:String]?
    var disableSilent = false
    var showRanges = true
    var tonicGain: Float = 0.32
    var tonicBrightness: Float = 0.7
    var tonicShimmer: Float = 0
    var audioOutputUID: String?
    var activeSetlistID: UUID?
    var tonicSound:ExternalSound?
    var tonicVelocitySelector:Bool?
    var tonicTimbre:Int?
    var tonicLastRoot:Int?
    var tonicLocked:Bool?
    // Appended after the original fields so the memberwise initializer keeps the
    // existing argument order; older settings files decode without them.
    var metronomeEnabled: Bool?
    var audioBufferFrames: Int?
    var metronomeSettings: MetronomeSettings? = nil
    /// Tempo shared by patches whose tempo is not locked to the patch.
    var liveTempo: Double?
    func validate() -> Bool {
        (0..<12).contains(tonicTimbre ?? 0) && (0..<12).contains(tonicLastRoot ?? 0) && (tonicSound == nil || tonicSound?.kind == .samplerPreset) && (audioBufferFrames.map { (0...8192).contains($0) } ?? true) && (audioOutputUID?.utf8.count ?? 0) <= 4096 && (modWheel.map { $0.isFinite && (0...1).contains($0) } ?? true) && (-1...15).contains(secondaryChannel ?? -1) && (0...127).contains(velocityMinimum ?? 0) && ((velocityMinimum ?? 0)...127).contains(velocityMaximum ?? 127) && (sourceNames?.count ?? 0) <= 512 && master.isFinite && (0...1).contains(master) && reverb.isFinite && (0...65).contains(reverb) && transition.isFinite && (0...15).contains(transition) && (-1...15).contains(midiChannel) && tonicGain.isFinite && (0...1).contains(tonicGain) && tonicBrightness.isFinite && (0...1).contains(tonicBrightness) && tonicShimmer.isFinite && (0...1).contains(tonicShimmer) && (metronomeSettings?.validate() ?? true) && (liveTempo.map { $0.isFinite && (PatchTransposition.minimumTempo...PatchTransposition.maximumTempo).contains($0) } ?? true)
    }
}
