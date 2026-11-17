import Foundation

/// Persistence contract for the metronome controls. The engine's timing is
/// covered natively by MetronomeTests; this keeps saved settings bounded and
/// readable across versions.
@main struct MetronomeSettingsTests {
    static func main() throws {
        // Settings written before the metronome block existed stay readable and
        // fall back to the engine defaults.
        var legacy = SessionSettings(selectedPatchID: nil, activeSnapshotID: nil, notesMode: nil, modWheel: nil)
        assert(legacy.validate())
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        object.removeValue(forKey: "metronomeSettings")
        let decodedLegacy = try JSONDecoder().decode(SessionSettings.self, from: JSONSerialization.data(withJSONObject: object))
        assert(decodedLegacy.metronomeSettings == nil && decodedLegacy.validate())

        // A saved metronome block written before this change has no count-in or
        // clock keys; both resolve to their defaults instead of invalidating it.
        var oldSettings = try JSONSerialization.jsonObject(with: JSONEncoder().encode(MetronomeSettings())) as! [String: Any]
        oldSettings.removeValue(forKey: "countInBars")
        oldSettings.removeValue(forKey: "followsMIDIClock")
        let oldBlock = try JSONDecoder().decode(MetronomeSettings.self, from: JSONSerialization.data(withJSONObject: oldSettings))
        assert(oldBlock.countInBars == 1 && !oldBlock.followsMIDIClock)

        var settings = MetronomeSettings()
        assert(settings.validate() && settings.visible && settings.followsMaster)
        assert(settings.level > 0 && settings.levelDBFS != nil)
        assert(settings.countInBars == 1 && !settings.followsMIDIClock)

        // Every control round-trips through settings.json.
        settings.visible = false
        settings.preset = 1
        settings.level = 0
        settings.beatVelocity = 0.25
        settings.downbeatEnabled = false
        settings.downbeatVelocity = 0.5
        settings.beatsPerBar = 7
        settings.accentEvery = 3
        settings.subdivision = 4
        settings.followsMaster = false
        settings.countInBars = 2
        settings.followsMIDIClock = true
        assert(settings.validate() && settings.levelDBFS == nil)
        legacy.metronomeSettings = settings
        assert(legacy.validate())
        let restored = try JSONDecoder().decode(SessionSettings.self, from: JSONEncoder().encode(legacy))
        assert(restored.metronomeSettings == settings)

        // A hand-edited or older value outside the engine's bounds is refused at
        // launch rather than being clamped silently.
        func rejected(_ change: (inout MetronomeSettings) -> Void) -> Bool {
            var value = MetronomeSettings()
            change(&value)
            return !value.validate()
        }
        assert(rejected { $0.preset = -1 })
        assert(rejected { $0.preset = MetronomeSettings.presets.count })
        assert(rejected { $0.level = -0.1 })
        assert(rejected { $0.level = 1.1 })
        assert(rejected { $0.level = .nan })
        assert(rejected { $0.beatVelocity = -0.1 })
        assert(rejected { $0.downbeatVelocity = 2 })
        assert(rejected { $0.beatsPerBar = 0 })
        assert(rejected { $0.beatsPerBar = 17 })
        assert(rejected { $0.accentEvery = -1 })
        assert(rejected { $0.accentEvery = 17 })
        assert(rejected { $0.subdivision = 0 })
        assert(rejected { $0.subdivision = 5 })
        assert(rejected { $0.countInBars = -1 })
        assert(rejected { $0.countInBars = 9 })
        var invalid = SessionSettings(selectedPatchID: nil, activeSnapshotID: nil, notesMode: nil, modWheel: nil)
        invalid.metronomeSettings = MetronomeSettings()
        invalid.metronomeSettings?.level = 2
        assert(!invalid.validate())

        // MIDI Clock is 24 pulses per quarter. The first tick establishes a
        // reference; 24 subsequent deltas produce 90 BPM, and a reset discards
        // the stale window instead of carrying a start/continue gap forward.
        var clock = MIDIClockTempo()
        var measured: Double?
        for i in 1...25 { measured = clock.tick(at: Double(i) / 36) }
        assert(measured != nil && abs(measured! - 90) < 0.01)
        assert(clock.tempo != nil && abs(clock.tempo! - 90) < 0.01)
        clock.reset()
        assert(clock.tempo == nil && clock.tick(at: 2) == nil)
        var gap = MIDIClockTempo()
        _ = gap.tick(at: 0)
        _ = gap.tick(at: 0.5)
        assert(gap.tick(at: 2) == nil, "a discontinuous timestamp must not change tempo")
        // The rejected gap must also discard the half-finished window; a later
        // 24-pulse window must measure 90 BPM, not a mixture across the gap.
        var afterGap: Double?
        for i in 1...24 { afterGap = gap.tick(at: 2 + Double(i) / 36) }
        assert(afterGap != nil && abs(afterGap! - 90) < 0.01)

        // Issue #108 records the receipt-time gap: tempo followed the moment a pulse
        // reached the main queue, so other main-thread work stretched every interval.
        // A CoreMIDI packet stamp dates the pulse at the driver; the receipt-only
        // path is kept here as the pre-fix witness the fix has to beat.
        let numer: UInt32 = 125, denom: UInt32 = 3 // an Apple mach timebase
        func ticks(_ seconds: Double) -> UInt64 {
            UInt64((seconds * 1_000_000_000 * Double(denom) / Double(numer)).rounded())
        }
        assert(MIDIClockTimestamp.at(packetTicks: 0, numer: numer, denom: denom, receipt: 42) == 42,
               "a zero stamp means as soon as possible and must fall back to the receipt")
        assert(MIDIClockTimestamp.at(packetTicks: ticks(900), numer: numer, denom: denom, receipt: 42) == 42,
               "a stamp on another epoch must fall back instead of inventing a tempo")
        assert(MIDIClockTimestamp.at(packetTicks: ticks(41.5), numer: 0, denom: 0, receipt: 42) == 42,
               "an unusable timebase must fall back to the receipt")
        assert(abs(MIDIClockTimestamp.at(packetTicks: ticks(41.5), numer: numer, denom: denom, receipt: 42) - 41.5) < 1e-6,
               "a stamp inside the latency window is the pulse time")
        assert(abs(MIDIClockTimestamp.seconds(hostTicks: ticks(2), numer: numer, denom: denom)! - 2) < 1e-6)
        let origin = 10_000.0, spacing = 60.0 / 120.0 / 24.0 // 24 pulses per quarter at 120 BPM
        var stamped = MIDIClockTempo(), receiptOnly = MIDIClockTempo()
        var stampedTempo: Double?, receiptTempo: Double?
        for pulse in 0...24 {
            let trueTime = origin + Double(pulse) * spacing
            // Each pulse is delivered a little later than the last: the main queue is
            // busy, which is exactly the bias the packet stamp removes.
            let delivered = trueTime + Double(pulse) * 0.0005
            stampedTempo = stamped.tick(at: MIDIClockTimestamp.at(packetTicks: ticks(trueTime), numer: numer,
                                                                 denom: denom, receipt: delivered)) ?? stampedTempo
            receiptTempo = receiptOnly.tick(at: delivered) ?? receiptTempo
        }
        assert(stampedTempo != nil && abs(stampedTempo! - 120) < 0.001,
               "the packet stamp must recover the true tempo")
        assert(receiptTempo != nil && abs(receiptTempo! - 120) > 1,
               "the receipt-only path must show the delivery delay this fix removes")

        // A deselected clock cannot send Stop through the source filter.
        // Release it on reassignment so the replacement source can start.
        let store = PerformanceStore()
        store.primarySourceID = 101
        let internalTempo = store.performedTempo
        store.metronomeSettings.followsMIDIClock = true
        func playClock(source: Int32, start: Double) {
            store.debugReceiveMIDIClock(0xFA, source: source, at: start)
            for pulse in 1...25 {
                store.debugReceiveMIDIClock(0xF8, source: source, at: start + Double(pulse) / 36)
            }
        }
        playClock(source: 101, start: 0)
        assert(abs(store.performedTempo - 90) < 0.01)
        store.primarySourceID = 102
        assert(store.clockTempo == nil && store.performedTempo == internalTempo)
        playClock(source: 102, start: 2)
        assert(abs(store.performedTempo - 90) < 0.01)
        store.stopAudio()
        assert(store.clockTempo == nil && store.performedTempo == internalTempo)

        print("PASS: metronome defaults, bounded controls, count-in and MIDI-clock settings, legacy settings and JSON round trip")
    }
}
