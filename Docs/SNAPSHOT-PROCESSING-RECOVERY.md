# Snapshot and effect processing transactions

Implementation follow-up for #123/#110, 2 November 2026. This extends [rack rollback](LIVE-GRAPH-ROLLBACK.md) to the supported snapshot-processing and effect-edit callers. It does not establish the cause of the reported intermittent AVFAudio `-1` or close the broader release milestone.

## Behavior

Snapshot recall prepares one processing batch across the affected layers. AU document states are size/type checked before mutation; changed states require a ready matching unit. Imported branch/routing edits, native effect parameters and rack pan changes must all succeed before host processing caches, C effect/pan controls, layer documents or the selected snapshot are published. Mixer pan is reapplied after graph completion, because the graph's ordinary mixer restoration otherwise reinstates its earlier values. Authored native-sampler processing remains the fallback for legacy layers without an explicit imported rack.

A processing batch captures old control state before any layer changes, even when its first structural edit occurs on a later layer. Rollback restores branch plans/tempo, built-in effect parameters, mixer settings and routing, then uses the existing note-intent recovery. Parameter-only frames do not stop the engine or reload samplers. Capturing rollback data runs on the main thread and never queries the engine's input singleton.

A rejected initial recall leaves its layer documents, prior snapshot selection, held/pedal ownership and saved bytes intact when graph rollback succeeds. It schedules no transition timer. Each later morph frame prepares changed processing across all affected layers before publishing that frame's layer/gain/control values. If a later frame rejects, the timer stops, pending gain ramps are pinned to the last committed document values, and the target snapshot is deselected rather than advertised as completed. Earlier successful frames are not undone. If graph rollback itself fails, the existing stopped/manual-retry policy clears stale note ownership.

Effect edits use the same processing acceptance result before changing their layer, per-snapshot sound state or saved session. A rejected edit does not publish those changes. Snapshot recall also rejects malformed gain/sound arrays and invalid transition timing before indexing or mutating them. Snapshot AU state recall now uses the rack's transaction/state-undo path; the unused direct in-place setter helper was removed.

## Evidence

`SnapshotProcessingTests` is included in the default library gate. It generates original sample fixtures and renders the production graph offline at 48 kHz stereo with 512-frame blocks. Its checks include:

- A gain/pan edit on an earlier layer followed by a later layer's injected post-routing failure: old documents/selection/saved bytes, stable tracked node count, held/pedal intent and rendered energy survive rollback.
- No morph timer remains after rejected initial recall; retry of the same target succeeds and changes rendered level, pan and layer processing.
- Effect-edit rejection preserves layer/snapshot/session data; accepted retry updates them.
- Malformed recall arrays are rejected without a crash or document change.
- Two generated AU candidates exercise the actual asynchronous loader and serialized state setters. Failure after the second state setter restores the previous states/documents; retry publishes both states. These candidates are Apple samplers, not third-party AU qualification.

The generated AU state adds a synthetic document marker to distinguish the request. The test checks the failure boundary and restoration, not that a sampler interprets that marker or that an arbitrary vendor setter exception is recoverable. No vendor samples, presets or plugin state are included in source.

See [verification commands, outcomes and frozen input hashes](Completion/snapshot-processing-verification.json). The earlier rollback evidence remains bound to its own source input set.

Final local verification: **105 program outcomes: 94 passed, 11 explicit private-fixture skips, zero failures**. One reported pass is the known private piano early return, not exercised piano evidence. The unsigned universal Mac and Simulator Release artifact gates passed. Runner coverage/contract, distribution refusal/content, shell syntax and whitespace checks passed; all 200 frozen source/test/project hashes were unchanged after verification. C DSP sources were unchanged, so the earlier sanitizer result was not rerun.

## Limits and remaining work

This adds supported processing-frame transactions, not an all-or-nothing rewind of an entire completed/partially completed performance transition. MIDI scheduling history, DSP history and phase-continuous waveform restoration remain outside the claim. Retriggered notes can be audible. Tonic root/instrument loading and external MIDI devices have their existing separate lifecycles; emitted MIDI cannot be recalled by an engine rollback.

Multi-AU **instrument/patch selection**, general channel-settings/configure callers, storage disappearance, actual third-party state/crash/hang behavior, the real intermittent `-1` trigger, hardware route/latency, physical mobile operation and long rehearsal qualification remain open. A generated failure after a setter is not evidence of real plugin process containment. The prior known private PianoHeldNoteTests early return remains unexercised without its fixture.

No GitHub issue edits/closure, commits, signing, installation or distribution were performed.

Subsequent work: [patch-wide instrument readiness](PATCH-READINESS.md) addresses coordinated loading/failure reporting for multi-AU instrument/patch selection. It does not claim simultaneous installation or qualification of the remaining device/plugin/rehearsal gates.

Subsequent work: [snapshot lifecycle and interruption](SNAPSHOT-LIFECYCLE.md) fixes post-Stop timer writes and stale patch/layer ownership, with a baseline reproduction and separate final verification.
