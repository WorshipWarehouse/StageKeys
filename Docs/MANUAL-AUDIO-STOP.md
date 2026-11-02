# Deliberate Stop and automatic audio startup

Implementation follow-up for live audio/MIDI recovery, 2 November 2026. This extends [snapshot lifecycle](SNAPSHOT-LIFECYCLE.md) and retains the separate hardware/release qualification gates.

## Reproduced defect and behavior

A generated virtual-CoreMIDI note reproduced audio restarting after explicit Stop Audio. The old `hardwareOn` path saw the stopped startup state and called Start automatically. MIDI refresh, automatic setup, focus return and the main view's appearance could also request startup without preserving the deliberate stop intent.

Stop now disables automatic startup for the current store/session. MIDI input remains connected and monitored, but incoming performance notes cannot restart the engine or acquire held-note ownership while stopped. Refresh MIDI and automatic setup still update input configuration without overriding Stop. The main view requests automatic startup rather than calling explicit Start. Failed audio is also excluded from automatic view startup; its diagnostic/generation remains intact until an explicit retry or the existing bounded retry policy acts.

An explicit Start/Retry resumes permission for automatic recovery. New stores/launches retain the original first-launch automatic startup policy; this is not a persisted preference disabling future launches. Scheduled startup/configuration callbacks remain generation-guarded, so Stop can invalidate a pending recovery request. The existing iOS interruption handler calls Stop and therefore also requires explicit resume; physical interruption behavior remains unqualified.

Library Audition now rejects while audio is stopped or a patch is still loading, without creating an isolated audition session or replacing a sound. The button remains available for ending an existing audition. Its disabled/help state tells the user to start audio or wait for loading, instead of accepting a preview that cannot be heard. Ordinary stopped-mode document editing remains available.

## Evidence

The minimal baseline regression was compiled against the unchanged pre-fix test core and failed with **MIDI input must not override Stop Audio**. Its generated source and log are retained in the temporary baseline directory; hashes are recorded separately from the final test.

`ManualAudioStopTests` is added to the default gate. It creates a disposable virtual CoreMIDI source, receives its packets through the real input path, and renders original generated native fixtures through the production stereo 48 kHz offline graph with 512-frame blocks. It verifies:

- A received note remains visible in the MIDI log after Stop without restarting audio or acquiring a held key.
- MIDI refresh/automatic setup and automatic view startup preserve Stop.
- Stopped audition is refused with actionable feedback.
- Explicit Start resumes, fresh MIDI reaches rendered audio, and an unrelated note-off from an ignored pitch cannot release the new note.
- Stop invalidates a simulated scheduled configuration restart.
- A fresh store can still activate through initial MIDI input while the deliberately stopped store stays stopped.

`GraphCompletionFailureTests` also checks that automatic startup does not retry a failed graph or replace its original failure/generation. Existing virtual CoreMIDI PlugAndPlay, snapshot lifecycle, patch readiness, Store and startup regressions remain default-gated.

See [commands, outcomes and frozen inputs](Completion/manual-audio-stop-verification.json). The tests do not establish physical keyboard/audio latency, real route interruption behavior or an interactive UI walkthrough.

Final local verification: **112 program outcomes: 101 passed, 11 explicit private-fixture skips, zero failures**. One reported pass remains the known private PianoHeldNoteTests early return; it is not exercised piano evidence. Both unsigned release artifact gates passed, together with runner coverage/contract, distribution refusal/content, shell syntax and whitespace checks. All 207 frozen source/test/project hashes were unchanged after verification. C DSP sources were unchanged, so the earlier sanitizer result was not rerun.

## Limits

This is an audio startup-intent policy, not a blanket MIDI disconnect. Monitoring, MIDI learning, controller configuration and their existing routing behavior remain unchanged; external-device controllers are not globally muted by this work. Packet timestamps are not rewritten, and no promise is made about physically sent events delayed until after explicit resume. Existing startup UI controls and retry timing remain unchanged apart from automatic main-view startup and the audition guard.

Physical mobile/route/storage behavior, vendor AU faults/state/sound, long rehearsal, release distribution and the real intermittent AVFAudio `-1` trigger remain unqualified. Prior records retain their original source input sets and skip limitations.

No GitHub issue changes/closure, commit/push, signing, installation or distribution were performed.

Subsequent work: [startup and loading Stop controls](AUDIO-OPERATION-CANCEL.md) makes the Stop action directly available during retry backoff and AU patch readiness, while preserving the deliberate-stop policy above.
