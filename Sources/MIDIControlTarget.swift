import Foundation

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
