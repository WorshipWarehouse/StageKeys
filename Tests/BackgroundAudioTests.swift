import Foundation

/// Lifecycle policy for the opt-in iOS background-audio setting.
///
/// This covers the decisions only. No engine, scene, session or device is opened,
/// so it runs in the default library gate on any machine. Physical interruption,
/// background and battery behavior remain device checks (#105).
@main struct BackgroundAudioTests {
    static func main() throws {
        // Leaving the foreground with background audio enabled changes nothing at
        // either phase: notes, sustain, tails and tempo keep running, including
        // through the transient inactive phase that precedes backgrounding.
        assert(BackgroundAudioPolicy.sceneAction(active: true, background: false, backgroundAudioEnabled: true, canSuspendAudio: true) == .none)
        assert(BackgroundAudioPolicy.sceneAction(active: true, background: false, backgroundAudioEnabled: false, canSuspendAudio: true) == .none)
        assert(BackgroundAudioPolicy.sceneAction(active: false, background: false, backgroundAudioEnabled: true, canSuspendAudio: true) == .none)
        assert(BackgroundAudioPolicy.sceneAction(active: false, background: true, backgroundAudioEnabled: true, canSuspendAudio: true) == .none)

        // Without the opt-in a transient inactive phase releases notes but never
        // tears the engine down; the performer has not left the app.
        assert(BackgroundAudioPolicy.sceneAction(active: false, background: false, backgroundAudioEnabled: false, canSuspendAudio: true) == .releaseNotes)
        assert(BackgroundAudioPolicy.sceneAction(active: false, background: false, backgroundAudioEnabled: false, canSuspendAudio: false) == .releaseNotes)

        // Entering the background without the opt-in stops audio and releases
        // voices, then restarts on return. macOS releases notes only.
        assert(BackgroundAudioPolicy.sceneAction(active: false, background: true, backgroundAudioEnabled: false, canSuspendAudio: true) == .suspendAudio)
        assert(BackgroundAudioPolicy.sceneAction(active: false, background: true, backgroundAudioEnabled: false, canSuspendAudio: false) == .releaseNotes)
        assert(BackgroundAudioPolicy.sceneAction(active: false, background: true, backgroundAudioEnabled: true, canSuspendAudio: false) == .none)
        assert(BackgroundAudioPolicy.canSuspendAudio == (BackgroundAudioPolicy.sceneAction(active: false, background: true, backgroundAudioEnabled: false) == .suspendAudio),
               "The platform default must agree with the platform capability")

        // An interruption always suspends first. Resuming needs both the system's
        // permission and a running engine before the interruption.
        assert(BackgroundAudioPolicy.interruptionAction(began: true, shouldResume: true, restoreAllowed: true) == .suspendAudio)
        assert(BackgroundAudioPolicy.interruptionAction(began: true, shouldResume: false, restoreAllowed: false) == .suspendAudio)
        assert(BackgroundAudioPolicy.interruptionAction(began: false, shouldResume: true, restoreAllowed: true) == .resumeAudio)
        assert(BackgroundAudioPolicy.interruptionAction(began: false, shouldResume: true, restoreAllowed: false) == .ignore,
               "A stopped engine is never restarted by an interruption notification")
        assert(BackgroundAudioPolicy.interruptionAction(began: false, shouldResume: false, restoreAllowed: true) == .ignore,
               "Without shouldResume the performer restarts audio explicitly")

        // Foreground activation consumes only a background suspension. An
        // interruption's resume intent belongs to the interruption-ended
        // notification, so an early active callback must not clear it.
        var resumeState = BackgroundAudioResumeState()
        resumeState.markInterruption(wasRunning: true)
        assert(!resumeState.consumeBackgroundResume(),
               "Interruption intent alone must not be consumed by foreground activation")
        assert(resumeState.interruptionResumeIntent)
        resumeState.markBackgroundSuspended()
        assert(resumeState.consumeBackgroundResume())
        assert(resumeState.interruptionResumeIntent,
               "Foreground activation must leave interruption resume intent for the interruption-ended notification")
        resumeState.clearInterruption()
        assert(!resumeState.interruptionResumeIntent)
        resumeState.markBackgroundSuspended()
        resumeState.markInterruption(wasRunning: true)
        resumeState.clear()
        assert(!resumeState.backgroundSuspendPending && !resumeState.interruptionResumeIntent,
               "Manual Stop must clear both resume intents")

        // Guidance must state both the benefit and the battery cost, and must not
        // imply that background audio is guaranteed.
        let on = BackgroundAudioPolicy.guidance(backgroundAudioEnabled: true)
        let off = BackgroundAudioPolicy.guidance(backgroundAudioEnabled: false)
        assert(on.contains("battery") && on.contains("sustain"))
        assert(off.contains("stops audio") && off.contains("return"))
        assert(on != off)

        // The opt-in persists with the rest of the session settings. Older files
        // have no field and keep the previous behavior (nil resolves to off).
        var settings = SessionSettings(selectedPatchID: nil, activeSnapshotID: nil, notesMode: nil, modWheel: nil)
        assert(settings.validate())
        assert(settings.backgroundAudioEnabled == nil)
        settings.backgroundAudioEnabled = true
        assert(settings.validate())
        let restored = try JSONDecoder().decode(SessionSettings.self, from: JSONEncoder().encode(settings))
        assert(restored.backgroundAudioEnabled == true)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        object.removeValue(forKey: "backgroundAudioEnabled")
        let legacy = try JSONDecoder().decode(SessionSettings.self, from: JSONSerialization.data(withJSONObject: object))
        assert(legacy.backgroundAudioEnabled == nil && legacy.validate(),
               "Settings written before this field existed must stay readable and mean off")

        print("PASS: background-audio scene/interruption policy, guidance and legacy settings decoding")
    }
}
