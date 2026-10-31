import Foundation

@main struct PatchTranspositionTests {
    static func main() {
        // Every Play In / Hear In pair resolves to a real, bounded interval.
        for play in 0..<12 {
            for hear in 0..<12 {
                let up = PatchTransposition.distance(playIn: play, hearIn: hear, direction: .up)
                let down = PatchTransposition.distance(playIn: play, hearIn: hear, direction: .down)
                let nearest = PatchTransposition.distance(playIn: play, hearIn: hear, direction: .nearest)
                assert((0...11).contains(up), "Up distance stayed inside one octave")
                assert((-11...0).contains(down), "Down distance stayed inside one octave")
                assert((-5...6).contains(nearest), "Nearest distance is the shortest signed interval")
                assert((play + up + 120) % 12 == hear, "Up distance reaches the hear key")
                assert((play + down + 120) % 12 == hear, "Down distance reaches the hear key")
                assert((play + nearest + 120) % 12 == hear, "Nearest distance reaches the hear key")
                assert(abs(nearest) <= abs(up) && abs(nearest) <= abs(down), "Nearest is never longer than a chosen direction")
                if (hear - play + 12) % 12 == 6 { assert(nearest == 6, "A tritone resolves upward") }
            }
        }
        // D performed, C sounding is the documented two-semitone downward move.
        assert(PatchTransposition.distance(playIn: 2, hearIn: 0, direction: .nearest) == -2)
        assert(PatchTransposition.distance(playIn: 2, hearIn: 0, direction: .up) == 10)
        assert(PatchTransposition.distance(playIn: 2, hearIn: 0, direction: .down) == -2)

        // Octave shifts wrap the sounding key without changing either key.
        assert(PatchTransposition.semitones(playIn: 2, hearIn: 0, direction: .nearest, octave: 0) == -2)
        assert(PatchTransposition.semitones(playIn: 2, hearIn: 0, direction: .nearest, octave: 1) == 10)
        assert(PatchTransposition.semitones(playIn: 2, hearIn: 0, direction: .nearest, octave: -1) == -14)
        assert(PatchTransposition.semitones(playIn: 2, hearIn: 2, direction: .nearest, octave: 2) == 24)
        assert(PatchTransposition.semitones(playIn: 0, hearIn: 11, direction: .up, octave: 2) == 24, "Octave shifts are bounded")
        assert(PatchTransposition.semitones(playIn: 0, hearIn: 11, direction: .down, octave: -2) == -24)
        assert(PatchTransposition.semitones(playIn: -4, hearIn: 99, direction: .nearest, octave: 9) == 23, "Out-of-range keys and octaves clamp")

        // Repeated changes return to exactly the original value; no drift.
        var transpose = PatchTransposition.semitones(playIn: 2, hearIn: 0, direction: .nearest, octave: 0)
        assert(transpose == -2)
        for _ in 0..<200 {
            transpose = PatchTransposition.semitones(playIn: 2, hearIn: 0, direction: .up, octave: 0)
            assert(transpose == 10)
            transpose = PatchTransposition.semitones(playIn: 2, hearIn: 0, direction: .down, octave: 0)
            assert(transpose == -2)
            transpose = PatchTransposition.semitones(playIn: 2, hearIn: 0, direction: .nearest, octave: 1)
            assert(transpose == 10)
            transpose = PatchTransposition.semitones(playIn: 2, hearIn: 0, direction: .nearest, octave: -1)
            assert(transpose == -14)
        }
        assert(transpose == -14)
        assert(PatchTransposition.semitones(playIn: 2, hearIn: 0, direction: .nearest, octave: 0) == -2)

        // Legacy patches stored the total only; the octave that explains it is
        // derived without rewriting the saved document.
        assert(PatchTransposition.octave(forTranspose: 0, playIn: 2, hearIn: 0, direction: .nearest) == 0)
        assert(PatchTransposition.octave(forTranspose: 12, playIn: 2, hearIn: 2, direction: .nearest) == 1)
        assert(PatchTransposition.octave(forTranspose: 11, playIn: 0, hearIn: 11, direction: .nearest) == 1)
        assert(PatchTransposition.octave(forTranspose: -24, playIn: 0, hearIn: 0, direction: .nearest) == -2)
        assert(PatchTransposition.octave(forTranspose: 48, playIn: 0, hearIn: 0, direction: .nearest) == 2, "Derived octave is bounded like the stored field")

        // Authored Easy Chord / Sequencer output is copied, never mutated.
        let authored = [60, 64, 67]
        assert(PatchTransposition.transposed(mapping: authored, by: -2) == [58, 62, 65])
        assert(PatchTransposition.transposed(mapping: authored, by: 12) == [72, 76, 79])
        assert(PatchTransposition.transposed(mapping: authored, by: 0) == authored)
        assert(PatchTransposition.transposed(mapping: [126, 127], by: 2) == [], "Output notes outside MIDI range are dropped, not wrapped")
        var program = MIDIProgram()
        program.chordMappings = [MIDIChordMapping(input: 60, output: authored)]
        program.sequenceMappings = [MIDISequenceMapping(input: 60, steps: [MIDISequenceStep(pitch: 60)])]
        let saved = program
        for key in 0..<12 {
            _ = PatchTransposition.transposed(mapping: program.chordMappings![0].output, by: PatchTransposition.distance(playIn: 0, hearIn: key, direction: .nearest))
        }
        assert(program == saved, "Repeated key changes must leave the authored program untouched")

        // Tempo lock: legacy (nil) recalls the patch tempo; an explicit unlock
        // shares one live tempo across patches.
        assert(PatchTransposition.recallsPatchTempo(locked: nil))
        assert(PatchTransposition.recallsPatchTempo(locked: true))
        assert(!PatchTransposition.recallsPatchTempo(locked: false))
        assert(PatchTransposition.resolvedTempo(locked: nil, patchTempo: 88, liveTempo: 120) == 88)
        assert(PatchTransposition.resolvedTempo(locked: true, patchTempo: 88, liveTempo: 120) == 88)
        assert(PatchTransposition.resolvedTempo(locked: false, patchTempo: 88, liveTempo: 120) == 120)
        assert(PatchTransposition.resolvedTempo(locked: false, patchTempo: 88, liveTempo: nil) == 88)
        assert(PatchTransposition.clampTempo(5) == 20 && PatchTransposition.clampTempo(400) == 300)
        assert(PatchTransposition.clampTempo(.nan) == 72 && PatchTransposition.clampTempo(87.6) == 88)

        // A tempo change keeps the musical phase of a running arpeggiator.
        let scheduler = MIDIFXProcessor(automaticallySchedule: false)
        var pitches: [Int] = []
        scheduler.onNote = { _, _, pitch, _ in pitches.append(pitch) }
        var arp = MIDIProgram(); arp.kind = .arpeggiator; arp.subdivision = 0.5
        scheduler.configure(channel: 0, program: arp, tempo: 120)
        scheduler.noteOn(channel: 0, key: 60, pitch: 60, velocity: 1)
        assert(pitches == [60], "The first step is emitted when the note arrives")
        scheduler.advance(to: 0.24); assert(pitches == [60], "An eighth note at 120 BPM is still pending")
        scheduler.advance(to: 0.25); assert(pitches == [60, 60], "The next step lands on the eighth note")
        scheduler.updateTempo(60)
        scheduler.advance(to: 0.7); assert(pitches == [60, 60], "The pending step keeps its rescaled position")
        scheduler.advance(to: 0.75); assert(pitches.count == 3, "The next step lands on the same musical beat at the new tempo")

        print("PASS: Play In/Hear In directions, octave wrapping, no drift, authored-mapping preservation, tempo lock and tempo phase")
    }
}
