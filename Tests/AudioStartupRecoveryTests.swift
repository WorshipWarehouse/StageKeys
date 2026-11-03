import Foundation
import AVFoundation

/// Deterministic, injected startup-failure matrix for the Store-level engine
/// lifecycle. Each scenario drives the production classification, retry and
/// recovery path with a synthetic NSError and an offline (manual-rendering)
/// engine, so it runs on a hosted Mac with no output device, physical interface,
/// competing audio app or real sleep/wake. It does not replace the AudioBox
/// reproduction, a real unplug/replug or a physical sleep/wake observation
/// recorded in issue #110.
@main struct AudioStartupRecoveryTests {
    /// The error observed before the main window opened (issue #110).
    static let observedBusy = NSError(domain: "com.apple.coreaudio.avfaudio", code: 2003329396,
        userInfo: [NSLocalizedDescriptionKey: "The operation couldn’t be completed. (com.apple.coreaudio.avfaudio error 2003329396.)"])

    static func wait(_ reason: String, _ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
        assert(predicate(), reason)
    }

    static func energy(_ store: PerformanceStore, blocks: Int = 20) throws -> Double {
        var total = 0.0
        for _ in 0..<blocks {
            let block = try store.audio.offlineBlock()
            for frame in 0..<Int(block.frameLength) {
                let value = block.floatChannelData![0][frame]
                assert(value.isFinite)
                total += Double(value * value)
            }
        }
        return total
    }

    /// Core Audio stops the engine before delivering a configuration change,
    /// and the store only restarts an engine that was already running. A bare
    /// notification would therefore be ignored, so stop the engine first.
    static func simulateEngineStop(_ store: PerformanceStore) {
        store.audio.stop()
        assert(store.started && !store.audio.running)
    }

    /// Offline route, reverb off so the note measurements are not tails.
    static func makeStore() throws -> PerformanceStore {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        store.reverb = 0
        try store.audio.prepareOffline()
        return store
    }

    static func main() throws {
        try busyOutputRetriesThenPlays()
        try repeatedFailureIsBoundedAndRecoversManually()
        try partialInitialisationIsCleanedUp()
        try routeChangeRecoversWithoutDuplicateEngine()
        try wakePreservesRunningAudioAndDeliberateStop()
        print("PASS audio startup recovery: busy retry, bounded repeated failure, format stop, partial-init cleanup, preserved session and injected route-change recovery")
    }

    /// Observed failure: the first start fails while another client owns the
    /// device, the retry succeeds, and the recovered engine renders notes.
    static func busyOutputRetriesThenPlays() throws {
        let store = try makeStore()
        defer { store.stopAudio() }
        var attempts = 0
        store.audio.debugStartFailure = {
            attempts += 1
            if attempts == 1 { return observedBusy }
            return nil
        }
        store.start()
        assert(attempts == 1)
        assert(store.audioIsStarting && store.audioOperationInProgress)
        assert(!store.started && !store.audio.running)
        assert(store.audioStartup.failure?.kind == .outputBusy)
        assert(store.audioFailureMessage?.contains("could not be opened") == true)
        assert(store.audioStatusText.hasPrefix("Starting"))
        wait("A recoverable busy output must retry automatically") { store.started }
        assert(attempts == 2)
        assert(store.audioStartup == .running && store.audioStatusText == "Running")
        assert(store.audio.running && !store.audioFailed && !store.audioOperationInProgress)
        store.audio.debugStartFailure = nil
        store.noteOn(60)
        assert(store.held.contains(60))
        let played = try energy(store)
        assert(played > 0.01, "Recovered engine must render the held note")
        store.noteOff(60)
        assert(store.held.isEmpty)
    }

    /// Repeated retryable failures stop after the bounded attempts, keep the
    /// session intact and still allow an explicit retry.
    static func repeatedFailureIsBoundedAndRecoversManually() throws {
        let store = try makeStore()
        defer { store.stopAudio() }
        store.metronome = true
        store.save()
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let setlistData = try Data(contentsOf: root.appendingPathComponent("setlist.json"))
        let settingsData = try Data(contentsOf: root.appendingPathComponent("settings.json"))
        let patchID = store.patch.id, layers = store.patch.layers
        let selected = store.selected, snapshot = store.activeSnapshot
        let controller = store.audio, rack = store.audio.externalRack
        var attempts = 0
        store.audio.debugStartFailure = { attempts += 1; return observedBusy }
        store.start()
        wait("Repeated retryable failures must end in a visible failed state") { store.audioFailed }
        assert(attempts == 3, "Three bounded attempts, never an endless retry loop: \(attempts)")
        assert(store.audioStatusText == "Failed")
        assert(!store.started && !store.audio.running && !store.audioOperationInProgress)
        assert(store.held.isEmpty)
        // No automatic path may retry a failed engine on its own.
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        store.startAutomatically(); store.refreshMIDI()
        assert(attempts == 3 && !store.started && store.audioFailed)
        // The session, selected patch and saved files are untouched.
        assert(store.patch.id == patchID && store.patch.layers == layers)
        assert(store.selected == selected && store.activeSnapshot == snapshot)
        assert(store.metronome, "The saved click choice must survive a failed start")
        let setlistAfter = try Data(contentsOf: root.appendingPathComponent("setlist.json"))
        let settingsAfter = try Data(contentsOf: root.appendingPathComponent("settings.json"))
        assert(setlistAfter == setlistData, "A failed start must not rewrite the setlist")
        assert(settingsAfter == settingsData, "A failed start must not rewrite settings")
        // Sample-rate/buffer rejection is a device setting, so it is reported
        // once and never retried behind the user's back.
        store.audio.debugStartFailure = { attempts += 1; return NSError(domain: NSOSStatusErrorDomain, code: -10868) }
        let beforeFormat = attempts
        store.start()
        assert(store.audioFailed && store.audioStartup.failure?.kind == .formatMismatch)
        assert(attempts == beforeFormat + 1, "A format rejection must not be retried automatically")
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        assert(attempts == beforeFormat + 1)
        assert(store.audioFailureMessage?.contains("sample rate") == true)
        assert(store.audioFailureMessage?.contains("/Users/") == false)
        assert(!store.started && !store.audio.running)
        // Explicit retry after the user resolves the setting recovers the same
        // engine and rack instance instead of creating a second one.
        store.audio.debugStartFailure = nil
        store.start()
        assert(store.started && store.audio.running && !store.audioFailed)
        assert(store.audio === controller)
        assert(store.audio.externalRack === rack, "Recovery must reuse the existing engine and rack")
        store.noteOn(61)
        let played = try energy(store)
        assert(played > 0.01)
        store.noteOff(61)
    }

    /// A failure reported after the engine started must stop the engine, clear
    /// the partial state and leave a retry that renders.
    static func partialInitialisationIsCleanedUp() throws {
        let store = try makeStore()
        defer { store.stopAudio() }
        let controller = store.audio
        var reported = 0
        store.audio.debugFailureAfterEngineStart = {
            reported += 1
            return NSError(domain: "com.apple.coreaudio.avfaudio", code: 7)
        }
        store.start()
        assert(reported == 1)
        assert(store.audioFailed && store.audioStartup.failure?.kind == .unknown)
        assert(!store.started, "A failed start must never publish a running session")
        assert(!store.audio.running, "Cleanup must stop an engine that already started")
        assert(store.held.isEmpty && !store.isNoteHeld(60))
        assert(store.audioFailureMessage?.contains("error 7") == true)
        store.audio.debugFailureAfterEngineStart = nil
        store.start()
        assert(store.started && store.audio.running && store.audio === controller)
        store.noteOn(62)
        let played = try energy(store)
        assert(played > 0.01)
        store.noteOff(62)
    }

    /// Route changes (unplug/replug) stop a running engine, release held notes,
    /// use the bounded retry while the device settles and never start a failed
    /// engine implicitly.
    static func routeChangeRecoversWithoutDuplicateEngine() throws {
        let store = try makeStore()
        defer { store.stopAudio() }
        store.start()
        assert(store.started && store.audio.running)
        let controller = store.audio, rack = store.audio.externalRack
        store.noteOn(60)
        assert(store.held.contains(60))
        var attempts = 0
        store.audio.debugStartFailure = { attempts += 1; return NSError(domain: NSOSStatusErrorDomain, code: -10876) }
        // The store observes configuration changes through the main operation
        // queue, so delivery is asynchronous even when posted from main.
        simulateEngineStop(store)
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: nil)
        wait("A route change must stop the running session") { !store.started && !store.audio.running }
        assert(store.held.isEmpty && !store.isNoteHeld(60), "Held notes must be released on a route change")
        wait("An unavailable route must exhaust the bounded retries") { store.audioFailed }
        assert(attempts == 3)
        assert(!store.started && !store.audio.running)
        // The device may still be settling: a second change must not start the
        // failed engine while the user has not asked for a retry.
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        assert(attempts == 3 && !store.started && !store.audio.running)
        // Reconnected route: the explicit start recovers the same engine, the
        // failed attempt left no sounding voice and notes are audible again.
        store.audio.debugStartFailure = nil
        store.start()
        assert(store.started && store.audio.running && !store.audioFailed)
        assert(store.audio === controller && store.audio.externalRack === rack)
        // Ownership, not a decay-threshold measurement: the failed attempt must
        // leave no held voice or pending note intent for the channel.
        assert(store.audio.externalRack?.debugActiveNoteCount(0) == 0,
               "The failed attempt must not retain a held voice")
        assert(store.audio.externalRack?.debugNoteIntentCount(0) == 0,
               "The failed attempt must not retain a pending note intent")
        store.noteOn(60)
        let played = try energy(store)
        assert(played > 0.01, "Notes must be audible after reconnecting the route")
        store.noteOff(60)
        assert(store.held.isEmpty)
    }

    /// A configuration change while running is the same delivery path as
    /// sleep/wake; it restarts audio and keeps the click choice. A deliberately
    /// stopped session must stay stopped.
    static func wakePreservesRunningAudioAndDeliberateStop() throws {
        let store = try makeStore()
        defer { store.stopAudio() }
        store.metronome = true
        store.start()
        assert(store.started && store.audio.running)
        simulateEngineStop(store)
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: nil)
        wait("A running engine should restart after a wake/route change") { store.started && store.audio.running }
        assert(!store.audioFailed)
        assert(store.metronome, "A wake/route change must keep the saved click choice")
        store.stopAudio()
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        assert(!store.started && !store.audio.running && store.audioStartup == .stopped,
               "A wake must not override a deliberate Stop")
    }
}
