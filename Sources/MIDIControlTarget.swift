import Foundation

/// Relative held-position drag with explicit handoff when hardware/snapshot CC1 changes.
struct ModulationWheelDrag {
    private var raw:Float?
    private var sent:Float?
    private var translation:Float=0
    static func quantized(_ value:Float)->Float {
        value.isFinite ? (min(1,max(0,value))*127).rounded()/127:0
    }
    mutating func update(current:Float,translation next:Float,height:Float)->Float {
        guard next.isFinite,height.isFinite,height>0 else{return Self.quantized(current)}
        if raw == nil || current != sent {raw=current.isFinite ? min(1,max(0,current)):0}
        raw=min(1,max(0,raw!-(next-translation)/height))
        translation=next;sent=Self.quantized(raw!)
        return sent!
    }
    mutating func end(){raw=nil;sent=nil;translation=0}
}

/// Persistent, stable identity for a MIDI CC assignment.
enum MIDIControlTarget: Codable, Hashable, Identifiable {
    case soundLevel(Int)
    case master
    case modulation
    case sustain
    case nextPatch
    case previousPatch
    case panic
    case snapshot(Int)

    var id: String {
        switch self {
        case .soundLevel(let index): return "soundLevel:\(index)"
        case .master: return "master"
        case .modulation: return "modulation"
        case .sustain: return "sustain"
        case .nextPatch: return "nextPatch"
        case .previousPatch: return "previousPatch"
        case .panic: return "panic"
        case .snapshot(let index): return "snapshot:\(index)"
        }
    }
    var title: String {
        switch self {
        case .soundLevel(let index): return "Sound \(index + 1) Level"
        case .master: return "Master Level"
        case .modulation: return "Modulation Wheel"
        case .sustain: return "Sustain Pedal"
        case .nextPatch: return "Next Patch"
        case .previousPatch: return "Previous Patch"
        case .panic: return "Panic"
        case .snapshot(let index): return "Snapshot \(index + 1)"
        }
    }
    var valid: Bool {
        switch self {
        case .soundLevel(let index): return (0..<15).contains(index)
        case .snapshot(let index): return (0..<16).contains(index)
        default: return true
        }
    }
    /// Buttons trigger once as a CC crosses from below 64 to at least 64.
    /// Sustain is a gate and must receive both its press and release values.
    var isRisingEdge: Bool {
        switch self {
        case .nextPatch, .previousPatch, .panic, .snapshot: return true
        default: return false
        }
    }
    static let reservedCCs: Set<Int> = [1, 64, 120, 123]
}

/// Input and learn rules shared by the store and the MIDI Learn UI. Kept pure so
/// conflicts, scaling and input acceptance are verifiable without hardware.
enum MIDIControllerRules {
    /// Linear scaling of an incoming 0–127 velocity into the configured range.
    static func velocity(_ value: UInt8, minimum: Int, maximum: Int) -> Float {
        let low = max(0, min(127, minimum))
        let high = max(low, min(127, maximum))
        let input = Float(max(0, min(127, Int(value))))
        return Float(low) / 127 + input / 127 * Float(high - low) / 127
    }
    /// A source/channel pair is accepted when it matches the primary or the
    /// secondary controller selection. -1 means any source or any channel; -2
    /// means the slot is unused.
    static func accepts(sourceID: Int32, channel: Int, source: Int32, inputChannel: Int) -> Bool {
        guard sourceID != -2 else { return false }
        return (sourceID == -1 || sourceID == source) && (channel == -1 || channel == inputChannel)
    }
    struct Assignment: Equatable {
        var assignments: [Int: MIDIControlTarget]
        var soundLevels: [Int: Int]
        /// Previous owner of the CC, so the UI can report a moved assignment.
        var displaced: MIDIControlTarget?
        var reserved: Bool
    }
    /// Learning a CC moves it from any other target, and a target owns at most
    /// one CC. Reserved controllers keep their fixed route and are never learned.
    static func assigning(_ cc: Int, to target: MIDIControlTarget,
                          assignments: [Int: MIDIControlTarget], soundLevels: [Int: Int]) -> Assignment {
        guard target.valid, (0...127).contains(cc), !MIDIControlTarget.reservedCCs.contains(cc) else {
            return Assignment(assignments: assignments, soundLevels: soundLevels, displaced: nil, reserved: true)
        }
        var assignments = assignments, soundLevels = soundLevels
        let existing = assignments[cc] ?? soundLevels[cc].map { MIDIControlTarget.soundLevel($0) }
        assignments.removeValue(forKey: cc)
        soundLevels.removeValue(forKey: cc)
        for other in assignments.filter({ $0.value == target }).keys { assignments.removeValue(forKey: other) }
        for other in soundLevels.filter({ MIDIControlTarget.soundLevel($0.value) == target }).keys { soundLevels.removeValue(forKey: other) }
        if case .soundLevel(let index) = target { soundLevels[cc] = index } else { assignments[cc] = target }
        return Assignment(assignments: assignments, soundLevels: soundLevels,
                          displaced: existing == target ? nil : existing, reserved: false)
    }
}

