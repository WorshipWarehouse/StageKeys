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
