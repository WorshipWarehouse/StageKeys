import Foundation

/// Deterministic checks for the MIDI FX deadline scheduler. The processor is
/// driven by an explicit clock here, so these tests do not depend on Timer,
/// audio hardware or wall-clock jitter.
@main struct MIDIFXTimerTests {
    static func main() {
        deadlineSelection()
        scheduledTimes()
        lookaheadEmission()
        pollingQuantization()
        print("PASS: earliest deadline selection, gate/step ordering and polling-grid quantization")
    }

    /// The armed deadline must be the earliest of the pending step, gate release
    /// and retrigger, and must disappear when the last source is released.
    static func deadlineSelection() {
        let p = MIDIFXProcessor(automaticallySchedule: false)
        var notes = 0
        p.onNote = { _, _, _, _ in notes += 1 }
        var arp = MIDIProgram()
        arp.kind = .arpeggiator
        arp.subdivision = 0.5
        arp.gate = 0.8
        p.configure(channel: 0, program: arp, tempo: 120)
        assert(p.nextDeadline == nil, "An idle scheduler has no deadline")

        p.noteOn(channel: 0, key: 60, pitch: 60, velocity: 1)
        assert(notes == 1, "The first step is emitted on note-on")
        guard let release = p.nextDeadline else { fatalError("Expected the first gate release") }
        assert(abs(release - 0.2) < 1e-9, "A 0.25 s step with 0.8 gate releases at 0.2 s")

        p.advance(to: 0.2)
        guard let step = p.nextDeadline else { fatalError("Expected the next step deadline") }
        assert(abs(step - 0.25) < 1e-9, "The next eighth note is due at 0.25 s")

        p.advance(to: 0.25)
        assert(notes == 2)
        guard let nextRelease = p.nextDeadline else { fatalError("Expected the second gate release") }
        assert(abs(nextRelease - 0.45) < 1e-9, "The second release precedes the 0.5 s step")

        p.noteOff(channel: 0, key: 60)
        assert(p.nextDeadline == nil, "Releasing the last source clears every deadline")

        // A retrigger deadline can precede the next step.
        var retrigger = arp
        retrigger.retriggerBeats = 0.5
        let q = MIDIFXProcessor(automaticallySchedule: false)
        q.configure(channel: 0, program: retrigger, tempo: 120)
        q.noteOn(channel: 0, key: 60, pitch: 60, velocity: 1)
        guard let first = q.nextDeadline else { fatalError("Expected a retrigger deadline") }
        assert(abs(first - 0.2) < 1e-9, "The earliest deadline still wins when a retrigger is pending")
    }

    /// Every emitted event must carry the musical time it belongs to, not the
    /// dispatch time, so a sample-accurate consumer can still place a late tick
    /// at the correct offset.
    static func scheduledTimes() {
        let p = MIDIFXProcessor(automaticallySchedule: false)
        var ons: [(Int, TimeInterval)] = []
        var offs: [(Int, TimeInterval)] = []
        p.onNoteAt = { _, key, _, _, _, at in ons.append((key, at)) }
        p.onOffAt = { _, key, _, at in offs.append((key, at)) }
        var arp = MIDIProgram()
        arp.kind = .arpeggiator
        arp.subdivision = 0.5
        arp.gate = 0.8
        p.configure(channel: 0, program: arp, tempo: 120)
        p.noteOn(channel: 0, key: 60, pitch: 60, velocity: 1)
        assert(ons.count == 1)
        assert(abs(ons[0].1) < 1e-9, "The first step belongs to note-on time")

        // Dispatch the 0.25 s step 10 ms late; it must still report 0.25 s.
        p.advance(to: 0.26)
        assert(ons.count == 2)
        assert(abs(ons[1].1 - 0.25) < 1e-9, "A late tick keeps the step's musical time")
        assert(offs.count == 1)
        assert(abs(offs[0].1 - 0.2) < 1e-9, "The first gate closes at its scheduled time")
        guard let gate = p.nextDeadline else { fatalError("Expected the late step's gate") }
        assert(abs(gate - 0.45) < 1e-9, "The late step's gate is measured from 0.25 s")

        // A tick that skips a whole period still reports the due step at 0.5 s.
        p.advance(to: 0.55)
        assert(ons.count == 3)
        assert(abs(ons[2].1 - 0.5) < 1e-9, "A skipped tick reports the due step, not the dispatch time")
        guard let nextGate = p.nextDeadline else { fatalError("Expected the skipped step's gate") }
        assert(abs(nextGate - 0.7) < 1e-9)
    }

    /// With a lookahead horizon the timer generates the next step before its
    /// deadline, while the event still reports the deadline itself.
    static func lookaheadEmission() {
        let p = MIDIFXProcessor(automaticallySchedule: false, lookahead: 0.01)
        var ons: [(Int, TimeInterval)] = []
        var offs: [(Int, TimeInterval)] = []
        p.onNoteAt = { _, key, _, _, _, at in ons.append((key, at)) }
        p.onOffAt = { _, key, _, at in offs.append((key, at)) }
        var arp = MIDIProgram()
        arp.kind = .arpeggiator
        arp.subdivision = 0.5
        arp.gate = 0.8
        p.configure(channel: 0, program: arp, tempo: 120)
        p.noteOn(channel: 0, key: 60, pitch: 60, velocity: 1)
        assert(ons.count == 1)

        // 0.20 s + 10 ms horizon stops before the 0.25 s step but releases the
        // 0.20 s gate, which is due inside the horizon.
        p.dispatch(at: 0.20)
        assert(ons.count == 1, "No step is due before 0.25 s")
        assert(offs.count == 1)
        assert(abs(offs[0].1 - 0.2) < 1e-9, "The gate releases at its musical time")

        // 0.24 s + 10 ms reaches 0.25 s: the step is emitted 10 ms early.
        p.dispatch(at: 0.24)
        assert(ons.count == 2, "The 0.25 s step is generated inside the horizon")
        assert(abs(ons[1].1 - 0.25) < 1e-9, "The event still reports 0.25 s")
        guard let gate = p.nextDeadline else { fatalError("Expected the step gate") }
        assert(abs(gate - 0.45) < 1e-9)

        // Later dispatches inside the horizon do not emit the same step twice.
        p.dispatch(at: 0.25)
        assert(ons.count == 2)

        // No lookahead keeps the old behavior: nothing is generated early.
        let q = MIDIFXProcessor(automaticallySchedule: false, lookahead: 0)
        var count = 0
        q.onNote = { _, _, _, _ in count += 1 }
        q.configure(channel: 0, program: arp, tempo: 120)
        q.noteOn(channel: 0, key: 60, pitch: 60, velocity: 1)
        q.dispatch(at: 0.24)
        assert(count == 1, "Without a horizon 0.24 s is still before the step")
    }

    /// Simulate a 5 ms polling timer versus a timer armed at each deadline. The
    /// expected step times are k * period; the only difference is when advance()
    /// is called. This isolates the scheduling grid from OS and audio jitter.
    static func pollingQuantization() {
        let grid = lateness(polling: true)
        let deadline = lateness(polling: false)
        print(String(format: "5 ms polling: max %.6f s, mean %.6f s, %d steps; deadline: max %.9f s, mean %.9f s, %d steps",
                     grid.max, grid.mean, grid.steps, deadline.max, deadline.mean, deadline.steps))
        fflush(stdout)
        assert(grid.steps > 200 && deadline.steps == grid.steps)
        assert(grid.max > 0.004 && grid.max <= 0.005001, "A 5 ms grid can be nearly one tick late")
        assert(grid.mean > 0.001 && grid.mean < 0.004)
        assert(deadline.max < 1e-6, "Deadline ticks emit on time")
    }

    static func lateness(polling: Bool) -> (max: Double, mean: Double, steps: Int) {
        let p = MIDIFXProcessor(automaticallySchedule: false)
        var emitted: [Double] = []
        var now = 0.0
        p.onNote = { _, _, _, _ in emitted.append(now) }
        var arp = MIDIProgram()
        arp.kind = .arpeggiator
        arp.subdivision = 0.5
        arp.gate = 1
        p.configure(channel: 0, program: arp, tempo: 132)
        let period = 60.0 / 132 * 0.5
        now = 0
        p.noteOn(channel: 0, key: 60, pitch: 60, velocity: 1)
        // Stop short of 60 s so the final step does not sit exactly on the
        // simulation end, where floating point could include it in one run and
        // not the other.
        let end = 59.0
        if polling {
            var tick = 0.0
            while tick <= end { now = tick; p.advance(to: tick); tick += 0.005 }
        } else {
            var step = 1
            // A real timer fires at or just after its deadline; a tick that lands
            // a hair early would not be due yet, so add a 1 ns delivery offset.
            while Double(step) * period <= end { now = Double(step) * period + 1e-9; p.advance(to: now); step += 1 }
        }
        var maximum = 0.0
        var total = 0.0
        for (index, at) in emitted.enumerated() {
            let late = at - Double(index) * period
            maximum = max(maximum, late)
            total += late
        }
        return (maximum, emitted.isEmpty ? 0 : total / Double(emitted.count), emitted.count)
    }
}
