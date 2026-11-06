import Foundation

/// Tempo-continuity acceptance coverage for #111: a tempo change must not
/// restart, double or drop a running arpeggiator or sequencer step, and it must
/// not leave a generated note sounding.
///
/// The scheduler is driven with an explicit clock, so these checks isolate the
/// musical phase arithmetic from timer latency, audio render blocks and hardware.
@main struct TempoContinuityTests {
    final class Recorder {
        var noteOns: [(time: TimeInterval, pitch: Int, key: Int)] = []
        var noteOffs: [(time: TimeInterval, key: Int)] = []
        var onsetTimes: [TimeInterval] { noteOns.map(\.time) }
        var pitches: [Int] { noteOns.map(\.pitch) }
    }

    static func recorder(_ scheduler: MIDIFXProcessor) -> Recorder {
        let recorder = Recorder()
        scheduler.onNoteAt = { _, key, pitch, _, _, at in
            recorder.noteOns.append((at, pitch, key))
        }
        scheduler.onOffAt = { _, key, _, at in
            recorder.noteOffs.append((at, key))
        }
        return recorder
    }

    /// Every generated note key must be released, or the tempo change left a
    /// stuck note behind.
    static func assertNoStuckNotes(_ recorder: Recorder, _ label: String) {
        let released = Set(recorder.noteOffs.map(\.key))
        let sounding = recorder.noteOns.map(\.key).filter { !released.contains($0) }
        assert(sounding.isEmpty, "\(label): every started note was released, stuck keys: \(sounding)")
    }

    /// A tempo change may not emit the same musical step twice.
    static func assertNoDoubleTrigger(_ recorder: Recorder, _ label: String) {
        assert(Set(recorder.onsetTimes).count == recorder.onsetTimes.count,
               "\(label): no two steps share an emission time")
    }

    static func main() {
        // --- Arpeggiator, 120 -> 60 BPM ------------------------------------
        // Eighth notes at 120 BPM are 0.25 s apart. Steps land at 0 and 0.25;
        // the change at 0.25 keeps musical beat 1.0, which is 0.75 s at 60 BPM.
        let slowDown = MIDIFXProcessor(automaticallySchedule: false)
        let slowRecorder = recorder(slowDown)
        var arp = MIDIProgram()
        arp.kind = .arpeggiator
        arp.subdivision = 0.5
        arp.gate = 0.8
        slowDown.configure(channel: 0, program: arp, tempo: 120)
        slowDown.noteOn(channel: 0, key: 60, pitch: 60, velocity: 1)
        assert(slowRecorder.onsetTimes == [0], "The first arpeggiator step is due on note-on")
        slowDown.advance(to: 0.24)
        assert(slowRecorder.onsetTimes == [0], "The next step is still pending before its deadline")
        slowDown.advance(to: 0.25)
        assert(slowRecorder.onsetTimes == [0, 0.25], "The second step lands on the eighth note")
        slowDown.updateTempo(60)
        slowDown.advance(to: 0.5)
        assert(slowRecorder.onsetTimes == [0, 0.25], "Halving the tempo must not fire an extra step")
        slowDown.advance(to: 0.75)
        assert(slowRecorder.onsetTimes == [0, 0.25, 0.75],
               "The pending step keeps its musical beat at the new tempo")
        assertNoDoubleTrigger(slowRecorder, "arpeggiator 120 -> 60")
        slowDown.noteOff(channel: 0, key: 60)
        slowDown.advance(to: 2)
        assertNoStuckNotes(slowRecorder, "arpeggiator 120 -> 60")

        // --- Arpeggiator, 60 -> 120 BPM ------------------------------------
        let speedUp = MIDIFXProcessor(automaticallySchedule: false)
        let fastRecorder = recorder(speedUp)
        speedUp.configure(channel: 0, program: arp, tempo: 60)
        speedUp.noteOn(channel: 0, key: 60, pitch: 60, velocity: 1)
        speedUp.advance(to: 0.5)
        assert(fastRecorder.onsetTimes == [0, 0.5], "Eighth notes at 60 BPM are half a second apart")
        speedUp.updateTempo(120)
        speedUp.advance(to: 0.74)
        assert(fastRecorder.onsetTimes == [0, 0.5], "Doubling the tempo must not fire the next step early")
        speedUp.advance(to: 0.75)
        assert(fastRecorder.onsetTimes == [0, 0.5, 0.75],
               "The pending step lands one eighth note after the change")
        assertNoDoubleTrigger(fastRecorder, "arpeggiator 60 -> 120")

        // --- Sequencer, 120 -> 60 BPM --------------------------------------
        // The authored pattern must continue where it was, not restart and not
        // repeat the step that was already emitted at the change.
        let sequence = MIDIFXProcessor(automaticallySchedule: false)
        let sequenceRecorder = recorder(sequence)
        var sequencer = MIDIProgram()
        sequencer.kind = .sequencer
        sequencer.subdivision = 0.5
        sequencer.gate = 0.5
        sequencer.steps = [
            MIDISequenceStep(pitch: 0), MIDISequenceStep(pitch: 4),
            MIDISequenceStep(pitch: 7), MIDISequenceStep(pitch: 12)
        ]
        sequence.configure(channel: 0, program: sequencer, tempo: 120)
        sequence.noteOn(channel: 0, key: 60, pitch: 60, velocity: 1)
        sequence.advance(to: 0.25)
        assert(sequenceRecorder.pitches == [60, 64], "The first two steps follow the authored order")
        sequence.updateTempo(60)
        sequence.advance(to: 0.5)
        assert(sequenceRecorder.pitches == [60, 64], "The change must not repeat the step at 0.25 s")
        sequence.advance(to: 0.75)
        assert(sequenceRecorder.pitches == [60, 64, 67],
               "The sequencer continues at the third authored step after the change")
        assertNoDoubleTrigger(sequenceRecorder, "sequencer 120 -> 60")
        sequence.noteOff(channel: 0, key: 60)
        sequence.advance(to: 2)
        assertNoStuckNotes(sequenceRecorder, "sequencer 120 -> 60")

        // --- Mapped sequencer: the input mapping still tracks the pattern ---
        let mapped = MIDIFXProcessor(automaticallySchedule: false)
        let mappedRecorder = recorder(mapped)
        var mappedProgram = MIDIProgram()
        mappedProgram.kind = .sequencer
        mappedProgram.subdivision = 0.5
        mappedProgram.gate = 0.5
        mappedProgram.sequenceMappings = [
            MIDISequenceMapping(input: 60, steps: [
                MIDISequenceStep(pitch: 40), MIDISequenceStep(pitch: 45), MIDISequenceStep(pitch: 52)
            ])
        ]
        mapped.configure(channel: 0, program: mappedProgram, tempo: 120)
        mapped.noteOn(channel: 0, key: 60, pitch: 60, velocity: 1)
        mapped.advance(to: 0.25)
        assert(mappedRecorder.pitches == [40, 45], "A mapped input plays its own authored steps")
        mapped.updateTempo(90)
        mapped.advance(to: 0.4)
        assert(mappedRecorder.pitches == [40, 45], "The mapped step is still pending after the change")
        mapped.advance(to: 0.6)
        assert(mappedRecorder.pitches == [40, 45, 52],
               "A mapped sequencer continues at its third step after a tempo change")
        assertNoDoubleTrigger(mappedRecorder, "mapped sequencer 120 -> 90")

        // --- Rapid alternating changes: no drift, no restart, no duplicates -
        let rapid = MIDIFXProcessor(automaticallySchedule: false)
        let rapidRecorder = recorder(rapid)
        rapid.configure(channel: 0, program: sequencer, tempo: 120)
        rapid.noteOn(channel: 0, key: 60, pitch: 60, velocity: 1)
        var clock: TimeInterval = 0
        var tempo = 120.0
        for step in 1...48 {
            clock += 60 / tempo * 0.5
            rapid.advance(to: clock)
            tempo = step.isMultiple(of: 2) ? 120 : 60
            rapid.updateTempo(tempo)
        }
        let expected = Array(stride(from: 0, to: rapidRecorder.pitches.count, by: 1))
            .map { [60, 64, 67, 72][$0 % 4] }
        assert(rapidRecorder.pitches == expected,
               "Forty-eight alternating tempo changes keep the authored step order without repeating or skipping: \(rapidRecorder.pitches)")
        assertNoDoubleTrigger(rapidRecorder, "rapid tempo changes")
        let strictlyIncreasing = zip(rapidRecorder.onsetTimes, rapidRecorder.onsetTimes.dropFirst())
            .allSatisfy { $0 < $1 }
        assert(strictlyIncreasing, "Step times keep advancing through every tempo change")

        // --- A redundant tempo write is a no-op -----------------------------
        let redundant = MIDIFXProcessor(automaticallySchedule: false)
        let redundantRecorder = recorder(redundant)
        redundant.configure(channel: 0, program: arp, tempo: 120)
        redundant.noteOn(channel: 0, key: 60, pitch: 60, velocity: 1)
        redundant.advance(to: 0.25)
        redundant.updateTempo(120)
        redundant.advance(to: 0.25)
        assert(redundantRecorder.onsetTimes == [0, 0.25],
               "Re-applying the current tempo must not retrigger or advance a step")
        assertNoDoubleTrigger(redundantRecorder, "redundant tempo write")
        redundant.noteOff(channel: 0, key: 60)
        redundant.advance(to: 1)
        assertNoStuckNotes(redundantRecorder, "redundant tempo write")

        print("PASS: arpeggiator and sequencer keep musical phase, authored step order and one trigger per step across tempo changes, and release every generated note")
    }
}
