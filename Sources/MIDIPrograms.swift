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
