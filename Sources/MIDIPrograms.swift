import Foundation

enum MIDIFXKind: String, Codable, CaseIterable { case bypass, arpeggiator, easyChord, octaveUp, sequencer }
enum MIDIArpStyle: String, Codable, CaseIterable { case up, down, upDown, downUp, random, chord, asPlayed }
struct MIDISequenceStep: Codable, Equatable {
    var pitch: Int = 0
    var velocity: Float = 1
    var enabled = true
}
struct MIDIChordMapping: Codable, Equatable {
    var input: Int
    var output: [Int]
}
struct MIDISequenceMapping: Codable, Equatable {
    var input: Int
    /// In a mapping, pitch is an absolute MIDI output note, not an interval.
    var steps: [MIDISequenceStep]
}
struct MIDIProgram: Codable, Equatable {
    var kind: MIDIFXKind = .bypass
    /// Beats per step: .25 is a sixteenth note, .5 an eighth note, 1 a quarter.
    var subdivision: Double = 0.25
    var gate: Double = 0.8
    var style: MIDIArpStyle = .up
    var octaves = 1
    var chordIntervals = [0, 4, 7]
    var steps = [MIDISequenceStep(), MIDISequenceStep(pitch: 7), MIDISequenceStep(pitch: 12), MIDISequenceStep(pitch: 7)]

    var swingGridBeats: Double?
    var swingAmount: Double?
    var repeatCount: Int?
    var retriggerBeats: Double?
    var velocityTarget: Float?
    var velocityDecaySeconds: Double?
    var retriggerVelocity: Bool?
    var transposeSteps: Int?
    var transposeDistance: Int?
    var freeRateSeconds: Double?
    var hold: Bool?
    var retriggerOnNote: Bool?
    var patternOffset: Int?
    /// Nil retains legacy note-off behavior. Imported gates can overlap adjacent steps.
    var releaseGeneratedOnKeyUp: Bool?
    var octaveBlend: Float?
    var arpVelocities: [Float]?
    var chordMappings: [MIDIChordMapping]?
    var sequenceMappings: [MIDISequenceMapping]?
    var sequenceVelocity: Float?

    var validated: MIDIProgram {
        var p = self
        p.subdivision = subdivision.isFinite ? min(4, max(0.03125, subdivision)) : 0.25
        p.gate = gate.isFinite ? min(2, max(0.01, gate)) : 0.8
        p.swingGridBeats=swingGridBeats.map{$0.isFinite ? min(4,max(0.03125,$0)):0.5}
        p.swingAmount=swingAmount.map{$0.isFinite ? min(1,max(0,$0)):0}
        p.repeatCount=repeatCount.map{min(128,max(1,$0))}
        p.retriggerBeats=retriggerBeats.map{$0.isFinite ? min(128,max(0.03125,$0)):4}
        p.velocityTarget=velocityTarget.map{$0.isFinite ? min(1,max(0,$0)):1}
        p.velocityDecaySeconds=velocityDecaySeconds.map{$0.isFinite ? min(60,max(0.001,$0)):1}
        p.transposeSteps=transposeSteps.map{min(8,max(0,$0))}
        p.transposeDistance=transposeDistance.map{min(48,max(-48,$0))}
        p.freeRateSeconds = freeRateSeconds.map { $0.isFinite ? min(1,max(0.01,$0)) : 0.02 }
        p.patternOffset = patternOffset.map { min(127,max(0,$0)) }
        p.octaves = min(4, max(1, octaves))
        p.chordIntervals = Array(Set(chordIntervals.map { min(48, max(-48, $0)) })).sorted()
        if p.chordIntervals.isEmpty { p.chordIntervals = [0] }
        p.steps = Array(steps.prefix(128)).map { MIDISequenceStep(pitch: min(48, max(-48, $0.pitch)), velocity: $0.velocity.isFinite ? min(1, max(0, $0.velocity)) : 0, enabled: $0.enabled) }
        if p.steps.isEmpty { p.steps = [MIDISequenceStep()] }
        func velocity(_ v: Float) -> Float { v.isFinite ? min(1, max(0, v)) : 0 }
        p.octaveBlend = octaveBlend.map(velocity)
        p.sequenceVelocity = sequenceVelocity.map(velocity)
        p.arpVelocities = arpVelocities.map { Array($0.prefix(128)).map(velocity) }
        if let mappings = chordMappings {
            var inputs = Set<Int>()
            p.chordMappings = mappings.prefix(128).compactMap { m in
                let input = min(127, max(0, m.input))
                guard inputs.insert(input).inserted else { return nil }
                return MIDIChordMapping(input: input, output: Array(Set(m.output.prefix(128).map { min(127, max(0, $0)) })).sorted())
            }
        }
        if let mappings = sequenceMappings {
            var inputs = Set<Int>()
            p.sequenceMappings = mappings.prefix(128).compactMap { m in
                let input = min(127, max(0, m.input))
                guard inputs.insert(input).inserted else { return nil }
                return MIDISequenceMapping(input: input, steps: m.steps.prefix(128).map { MIDISequenceStep(pitch: min(127, max(0, $0.pitch)), velocity: velocity($0.velocity), enabled: $0.enabled) })
            }
        }
        return p
    }
}

/// How a Play In → Hear In key change chooses its semitone direction.
///
/// `nearest` keeps the smallest interval (a tritone resolves upward); `up` and
/// `down` let the performer keep moving in one direction instead of accepting
/// the shorter move. The choice is patch data, so it survives save and reload.
enum KeyDirection: String, Codable, CaseIterable {
    case nearest, up, down

    var label: String {
        switch self {
        case .nearest: return "Nearest"
        case .up: return "Up"
        case .down: return "Down"
        }
    }
}

/// Patch-level Play In / Hear In arithmetic and tempo-lock resolution.
///
/// The stored `Patch.transpose` stays the single playback value; these helpers
/// only compute it when a control changes, so a setlist written by an older
/// version keeps playing exactly as before. They live beside the MIDI program
/// mapping because both are hardware-free note arithmetic shared by the model,
/// the scheduler and the tests.
enum PatchTransposition {
    static let minimumTranspose = -24
    static let maximumTranspose = 24
    static let minimumOctave = -2
    static let maximumOctave = 2
    static let minimumTempo = 20.0
    static let maximumTempo = 300.0

    static func clampKey(_ key: Int) -> Int { min(11, max(0, key)) }
    static func clampOctave(_ octave: Int) -> Int { min(maximumOctave, max(minimumOctave, octave)) }
    static func clampTranspose(_ semitones: Int) -> Int { min(maximumTranspose, max(minimumTranspose, semitones)) }
    static func clampTempo(_ tempo: Double) -> Double {
        guard tempo.isFinite else { return 72 }
        return min(maximumTempo, max(minimumTempo, tempo.rounded()))
    }

    /// Semitone distance from the performed key to the sounding key.
    static func distance(playIn: Int, hearIn: Int, direction: KeyDirection) -> Int {
        let play = clampKey(playIn)
        let hear = clampKey(hearIn)
        switch direction {
        case .nearest:
            // -5…6: a tritone moves up rather than down so repeated key changes
            // do not alternate direction unpredictably.
            let raw = hear - play
            return ((raw + 5) % 12 + 12) % 12 - 5
        case .up:
            return (hear - play + 12) % 12
        case .down:
            return -((play - hear + 12) % 12)
        }
    }

    /// Total patch transposition in semitones: the key distance plus an explicit
    /// octave offset, bounded like the stored field.
    static func semitones(playIn: Int, hearIn: Int, direction: KeyDirection, octave: Int) -> Int {
        clampTranspose(distance(playIn: playIn, hearIn: hearIn, direction: direction) + 12 * clampOctave(octave))
    }

    /// Octave offset that explains an already stored transposition. Legacy
    /// patches stored the total only, so this is derived rather than migrated:
    /// nothing in the saved document is rewritten.
    static func octave(forTranspose transpose: Int, playIn: Int, hearIn: Int, direction: KeyDirection) -> Int {
        let key = distance(playIn: playIn, hearIn: hearIn, direction: direction)
        let remainder = transpose - key
        let octave = Int((Double(remainder) / 12).rounded(.towardZero))
        return clampOctave(octave)
    }

    /// Applies a patch-relative offset to an authored output note. Notes outside
    /// the MIDI range are dropped, never wrapped onto a neighbouring pitch.
    static func transposed(pitch: Int, by semitones: Int) -> Int? {
        let value = pitch + semitones
        return (0...127).contains(value) ? value : nil
    }

    static func transposed(mapping: [Int], by semitones: Int) -> [Int] {
        mapping.compactMap { transposed(pitch: $0, by: semitones) }
    }

    /// `nil` keeps the legacy behaviour: the patch recalls its own tempo.
    /// An explicit `false` means the live tempo is shared and patch switches
    /// keep the tempo the performer is already playing at.
    static func recallsPatchTempo(locked: Bool?) -> Bool { locked ?? true }

    static func resolvedTempo(locked: Bool?, patchTempo: Double, liveTempo: Double?) -> Double {
        let patch = clampTempo(patchTempo)
        guard !recallsPatchTempo(locked: locked) else { return patch }
        guard let liveTempo else { return patch }
        return clampTempo(liveTempo)
    }
}
