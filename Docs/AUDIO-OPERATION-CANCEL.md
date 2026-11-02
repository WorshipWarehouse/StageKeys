# Startup and patch-loading Stop controls

Implementation follow-up, 2 November 2026, to [deliberate Stop](MANUAL-AUDIO-STOP.md). This exposes the existing cancellation action during operations that previously left the normal startup control disabled.

## Behavior

The performance screen's startup/loading banner now includes an enabled **Stop Audio** action. Audio Settings also offers **Stop Audio and Cancel Loading** while startup/retry or AU patch loading is pending, independently of the existing disabled startup toggle. Both actions use the same Store Stop path: invalidate queued retries and patch/configuration request generations, clear performance note ownership, stop playback and preserve deliberate-stop intent until explicit Start.

The progress indicator and actions share one state predicate covering engine startup/retry and patch readiness. A ready, stopped or terminally failed state does not advertise a pending operation. Existing automatic retry bounds remain unchanged. Cancelling a pending patch does not erase its authored settings, silently change selection or convert a late cancelled callback into a new failed-load quarantine entry.

This is logical cancellation of pending host ownership and queued work when the main loop can handle the action. It does not preempt a synchronous native API call, kill an AU worker or prove containment of a blocked/crashed vendor process. A plugin's underlying request can finish later; existing callback/deadline and recovery-journal ownership still apply. Stop does not clear quarantine or automatically relaunch audio.

## Evidence

`AudioOperationCancelTests` is added to the default gate. A DEBUG-only engine-start fault drives the real Store startup classifier and retry scheduler using a generated busy-output error. The hook is absent from release builds. The test verifies:

- Startup backoff reports a cancellable operation; Stop prevents its queued retry and subsequent automatic/refresh wake.
- Without cancellation, the existing three-attempt policy terminates in failure; automatic view startup does not retry that terminal state.
- Explicit retry starts a new operation, which can also be stopped without later attempts.
- Clearing the generated fault permits a healthy native start.
- A two-AU pending patch exposes the same cancellation state. Late generated success/failure callbacks cannot attach the cancelled candidate, restart playback, replace failure evidence or create quarantine entries.
- Authored session bytes remain unchanged by cancellation, and a later explicit native start renders fresh notes.

The route uses original generated WAV fixtures and production stereo 48 kHz offline rendering with 512-frame blocks. No real busy audio device or third-party plugin failure is caused. Existing manual Stop, startup, patch readiness, recovery journal, snapshot lifecycle and Store regressions remain default-gated.

See [verification commands, outcomes and frozen inputs](Completion/audio-operation-cancel-verification.json). The new controls are compiled in unsigned Mac and Simulator artifacts. No interactive UI walkthrough, physical-device interruption latency or mobile layout qualification is inferred from compilation.

Final local verification: **113 program outcomes: 102 passed, 11 explicit private-fixture skips, zero failures**. One reported pass remains the known private PianoHeldNoteTests early return; it is not exercised piano evidence. Both unsigned release artifact gates passed, together with runner coverage/contract, distribution refusal/content, shell syntax and whitespace checks. All 208 frozen source/test/project hashes were unchanged after verification. C DSP sources were unchanged, so the earlier sanitizer result was not rerun.

## Remaining scope

Blocked main-thread/native calls cannot process a new UI click until they return. Real route contention, vendor process cancellation/containment, registry/device latency, physical mobile, prolonged rehearsal, public distribution and the original intermittent AVFAudio `-1` trigger remain qualification gaps. Prior records retain their own input sets and private-fixture limitations.

No GitHub issue changes/closure, commit/push, signing, installation or distribution were performed.

Subsequent work: [bounded outstanding AU requests](AU-LOAD-ADMISSION.md) prevents repeated cancellation/retry from admitting unlimited backend work and preserves capacity ownership until callbacks actually return.
