import Foundation

@main struct AudioStartupTests {
    static func main() {
        let route = "AudioBox USB 96"

        // The observed AVFAudio failure on a machine with competing audio apps.
        let busy = AudioStartupClassifier.classify(
            NSError(domain: "com.apple.coreaudio.avfaudio", code: 2003329396),
            routeName: route)
        assert(busy.kind == .outputBusy, "Unspecified Core Audio error should be treated as busy/unavailable")
        assert(busy.recoverable, "A busy output is worth a bounded automatic retry")
        assert(busy.message.contains(route), "The failure should name the selected route")
        assert(!busy.message.contains("/Users/"), "Raw descriptions and paths must not leak into the message")

        let unavailable = AudioStartupClassifier.classify(
            NSError(domain: NSOSStatusErrorDomain, code: -10876), routeName: route) // kAudioUnitErr_NoConnection
        assert(unavailable.kind == .outputUnavailable)
        assert(unavailable.recoverable)
        assert(unavailable.message.contains(route))

        let format = AudioStartupClassifier.classify(
            NSError(domain: NSOSStatusErrorDomain, code: -10868), routeName: route)
        assert(format.kind == .formatMismatch)
        assert(!format.recoverable, "A format rejection needs a user device change, not a blind retry")
        assert(format.message.contains("sample rate"))
        assert(format.message.contains(route))

        let interrupted = AudioStartupClassifier.classify(
            NSError(domain: "com.apple.coreaudio.avfaudio", code: 561017460,
                    userInfo: [NSLocalizedDescriptionKey: "Audio was interrupted by another application."]),
            routeName: route)
        assert(interrupted.kind == .interrupted)
        assert(interrupted.recoverable)

        let denied = AudioStartupClassifier.classify(
            NSError(domain: "com.apple.coreaudio.avfaudio", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Permission denied."]),
            routeName: route)
        assert(denied.kind == .permissionDenied)
        assert(!denied.recoverable)

        let posixBusy = AudioStartupClassifier.classify(
            NSError(domain: NSPOSIXErrorDomain, code: 16), routeName: route)
        assert(posixBusy.kind == .outputBusy)
        assert(posixBusy.recoverable)

        let leak = AudioStartupClassifier.classify(
            NSError(domain: NSOSStatusErrorDomain, code: 42,
                    userInfo: [NSLocalizedDescriptionKey: "/Users/private/Samples/secret.wav"]),
            routeName: route)
        assert(leak.kind == .unknown)
        assert(!leak.recoverable, "Unexpected failures are not retried without a known cause")
        assert(!leak.message.contains("/Users/"), "Unexpected descriptions must not leak paths")
        assert(leak.message.contains("error 42"))

        let unnamed = AudioStartupClassifier.classify(
            NSError(domain: NSOSStatusErrorDomain, code: 2003329396), routeName: "   ")
        assert(unnamed.routeName == nil)
        assert(unnamed.message.contains("The selected audio output"),
               "A blank route must fall back to a neutral, non-identifying description")

        // Bounded retry: three attempts, two waits, then a visible failure.
        let policy = AudioStartupRetryPolicy()
        assert(policy.maximumAttempts == 3)
        assert(policy.delay(afterFailedAttempt: 0) == nil)
        assert(policy.delay(afterFailedAttempt: 1) == 0.25)
        assert(policy.delay(afterFailedAttempt: 2) == 0.75)
        assert(policy.delay(afterFailedAttempt: 3) == nil)
        let single = AudioStartupRetryPolicy(maximumAttempts: 1, delays: [])
        assert(single.delay(afterFailedAttempt: 1) == nil)

        // Unplug/replug, sleep/wake and route changes all arrive as engine
        // configuration changes; only a previously running engine is restarted.
        assert(AudioStartupRecovery.shouldRestartAfterConfigurationChange(started: true, engineRunning: false))
        assert(!AudioStartupRecovery.shouldRestartAfterConfigurationChange(started: true, engineRunning: true))
        assert(!AudioStartupRecovery.shouldRestartAfterConfigurationChange(started: false, engineRunning: false))
        assert(!AudioStartupRecovery.shouldRestartAfterConfigurationChange(started: false, engineRunning: true))

        // State transitions used by the store and the non-blocking UI.
        var state = AudioStartupState.stopped
        assert(!state.isStarting && !state.isFailed && state.failure == nil)
        state = .starting(attempt: 1)
        assert(state.isStarting && !state.isFailed)
        state = .retrying(attempt: 2, delay: 0.25, failure: busy)
        assert(state.isStarting && state.failure == busy)
        state = .running
        assert(!state.isStarting && !state.isFailed && state.failure == nil)
        state = .failed(busy)
        assert(state.isFailed && !state.isStarting && state.failure == busy)

        print("PASS: audio startup classification, route-safe messages, bounded retry policy and state transitions")
    }
}
