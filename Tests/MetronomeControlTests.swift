import Foundation
import AVFoundation

/// Runtime contract for the metronome controls the C engine cannot see: when a
/// Count In request is allowed to reach the scheduler, how it fails while audio
/// is stopped, and that the chosen bars and clock opt-in persist.
@main struct MetronomeControlTests {
    static func main() throws {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        store.stopAudio()
        assert(!store.started && !store.audio.running)
        store.metronomeSettings.countInBars = 2

        // A manual Stop revokes automatic start. Count In must not schedule into
        // the stopped engine and must explain the recovery action.
        store.message = nil
        let scheduled = store.audio.debugCountInRequests
        store.countIn()
        assert(store.audio.debugCountInRequests == scheduled, "A stopped engine must not schedule a count-in")
        assert(store.message?.contains("Start audio") == true)
        assert(!store.started && !store.audio.running)

        // Manual rendering runs the real production graph without a device, so
        // the accepted path matches the Store call used in performance.
        try store.audio.prepareOffline()
        store.start()
        assert(store.started && store.audio.running)
        store.message = nil
        store.countIn()
        assert(store.audio.debugCountInRequests == scheduled + 1)
        assert(store.message == nil && store.metronomeSettings.countInBars == 2)
        assert(!store.metronome, "Count In must not change the normal click setting")

        // External clock owns the timing; Count In is internal-clock only.
        store.metronomeSettings.followsMIDIClock = true
        store.message = nil
        store.countIn()
        assert(store.audio.debugCountInRequests == scheduled + 1)
        assert(store.message?.contains("internal clock") == true)
        store.metronomeSettings.followsMIDIClock = false

        // Zero bars hides the action; a direct call stays inert without a message.
        store.metronomeSettings.countInBars = 0
        store.message = nil
        store.countIn()
        assert(store.audio.debugCountInRequests == scheduled + 1 && store.message == nil)

        // Save/restart contract: both new controls survive settings.json and
        // still validate against the engine bounds.
        store.metronomeSettings.countInBars = 3
        store.metronomeSettings.followsMIDIClock = true
        store.save()
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let settings = try JSONDecoder().decode(SessionSettings.self,
            from: Data(contentsOf: root.appendingPathComponent("settings.json")))
        assert(settings.metronomeSettings?.countInBars == 3 && settings.metronomeSettings?.followsMIDIClock == true)
        assert(settings.metronomeSettings?.validate() == true)
        store.stopAudio()
        print("PASS: Count In is gated by running audio and internal clock, and its bars persist")
    }
}
