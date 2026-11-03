# Live sound-change preparation and diagnostics — #123

Implementation follow-up to the 2 November 2026 completion audit. The owner approved the first implementation milestone. This change establishes a bounded failure-preservation path; it does not close #123 or establish the cause of the intermittent live AVFAudio `-1` report.

## Reproduced failure

`PerformanceStore.commitLayer` previously updated snapshots, panicked notes, replaced the document layer and saved it before verifying a proposed sound's managed file. `AudioController.configure` removed the playing external instrument before loading the replacement. If the managed file was missing, the replacement failed and the failure callback removed the channel again. The result could be a silent module whose document and saved settings described the unavailable replacement.

The new generated regression (`Tests/LiveSoundChangeTests.swift`) failed against source baseline `6a253130196e8beca471a575a45c1834d52cedf8` at its first preservation assertion: **A rejected replacement must retain the previous layer and fader**. This is an independently reproduced missing-resource defect, not a reproduction of the user's intermittent `-1` trigger.

## Implemented boundary

Before `commitLayer` cancels a preview, changes snapshots, panics a channel or writes settings, `AudioController.prepareSoundChange` validates known local resources. The same guard precedes controller configuration, so direct controller callers reject a known invalid proposal before cache, gain or pan changes.

The check covers missing/invalid managed file identities, a structurally invalid AU instrument identity, and known absolute/file-URL sample references that the existing sampler verifier can check. It does not instantiate an AU or claim that a valid-looking instrument will load. It preserves the existing bounded 16 MB preset-reference inspection; undecodable/oversized/unrecognized and relative resolver state is still handled by the actual loader, not certified by preflight.

On a preparation failure the old graph is never stopped or rebuilt. The previous held sample, sustain state, active slot, snapshot data, layer gain/pan and session bytes remain intact. A later valid selection still commits. Source samples and presets are read only.

## Failure evidence and messages

Local **Copy Support Diagnostics** now optionally includes the last failed audio change:

- random failure-record UUID, phase, 1-based sound slot and graph generation;
- engine-running flag, finite sample rate when available, numeric error code and allowlisted error domain;
- `previousSoundRetained: true` originally covered preparation rejection; the native-load follow-up also records unchanged instrument/cache retention on a pre-attachment decoder failure. The flag alone does not certify document rollback or uninterrupted audio for every caller.

No original error description, arbitrary error-domain string, private filename/path, patch name, device identity, plugin state or sample payload is retained. The existing support report separately contains the current device-reported buffer/rate/latency fields. There is no upload or disk-based diagnostic history, and current device status must not be mistaken for a captured historical route. The UUID identifies a failure record, not a traced end-to-end transaction.

The user message explains whether preparation retained the old state or a later audio change needs attention, with a plain-language phase, numeric code and recovery guidance. `withGraphChanges` records a failure while rethrowing the original error type, preserving callers' typed catch behavior. Graph generations increment when the rack starts a real graph edit, not on a preflight rejection or a no-op batch.

## Regression evidence

The generated test covers:

- an existing managed sample sustaining during a rejected replacement;
- unchanged instrument identity, graph generation, unrelated channel, held-note/sustain state, level, snapshots and saved session bytes;
- a deterministic injected AVFAudio `-1` **before mutation**, with no private error-text leakage;
- an existing preset whose referenced sample is missing;
- direct controller preparation rejection and successful subsequent replacement;
- a graph-transaction error recorded without changing the original thrown NSError or promising rollback.

SupportDiagnosticsTests verifies round-trip of the new optional record, absence of private descriptions/arbitrary domains, finite-rate handling and decoding reports without the optional field. The new sound-change program is in the default library gate.

First-stage local verification, before the native-load follow-up: **100 program results: 89 passed, 11 explicit private-fixture skips, zero failures**. One pass status is the previously documented private PianoHeldNoteTests early return; it is not exercised piano validation. Unsigned universal Mac and iOS Simulator Release artifact gates pass. Runner coverage/contract, distribution-refusal, shell syntax and whitespace checks pass. The initial broader test run caught the missing-content wording regression; its assertion was preserved and the final run passes. DSP code was unchanged, so the prior sanitizer result was not rerun.

See [implementation verification](Completion/live-change-verification.json) for final commands, outcomes and input hashes. No physical keyboard/device test, audible reference comparison, third-party fault-AU run or long soak is claimed.

## Remaining milestone work

Preparation has a time-of-check/time-of-use window. Files can disappear after it succeeds; malformed sources, AU instantiation/state restoration, effect topology changes and engine restarts can still fail after document/graph mutation. The [native-load follow-up](NATIVE-LOAD-RECOVERY.md) now removes destructive pre-load removal/cache updates and preserves native document state on decoder rejection. Later graph/state/processing completion and `Store.applyPatch` still have broader transaction requirements; asynchronous AU documents remain separately qualified.

Next: fault-inject failures after candidate attachment, state restoration, sampler restoration and engine restart; capture the previous graph/document/held-note state at each boundary; then design the smallest staged commit or controlled recovery justified by those reproductions. In particular, the rack currently suppresses errors from finishing graph changes while another operation error is being thrown; primary and cleanup failure evidence need separate ownership. No old sound or preset should be destroyed to simulate a failure. Capture at least one real user `-1` occurrence with route/rate/buffer and triggering operation before claiming that reported defect fixed. Live #110 AudioBox contention/unplug/sleep evidence remains outstanding.

Subsequent work: [audio device failure state and diagnostics](AUDIO-DEVICE-FAILURE-STATE.md) records numeric failures for explicit output/buffer changes and preserves the Tonic Pad and click across rejected or successful device-setting transactions. Its macOS execution and real AudioBox/unplug evidence remain unverified; the separate configuration-change/startup path is owned by #130.
