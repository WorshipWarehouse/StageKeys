# Resource availability and stopped-mode repair

Implementation follow-up for #123/#110, 2 November 2026. This follows [patch readiness](PATCH-READINESS.md) and does not close the broader release milestone.

## Behavior

During live playback, patch selection checks the proposed native sound files and known sampler references before changing selection, cancelling a transition or releasing current notes. The check explicitly revalidates resources even when the requested sound identity is already cached. A known missing resource leaves the current patch, snapshot, held/pedal ownership and saved bytes unchanged. Selection attempts still cancel pending plugin-editor presentation, preserving the existing handoff contract.

Managed native sound inputs and known absolute/file-URL sample references must resolve to readable regular files. Directories and broken symlinks do not count as audio files; readable file symlinks remain supported. The bounded preset inspection no longer stops after the first 4,096 references. Duplicate paths are checked once per document. Relative/opaque references remain with the sampler's resolver. Preset inspection retains its existing 16 MB/type parsing bounds: oversized, unparseable or differently serialized reference inventories are not proven complete by this check and remain subject to the actual loader.

Immediately before a structural edit stops the engine, the rack checks the known references needed to restore its active samplers. Retired effect-tail samplers are excluded because completion does not reload them. If a resident sample has disappeared from storage, an edit requiring reload can reject before stopping the engine or advancing graph generation. Processing batches restore any earlier control changes and replay owned note intent from resident voices without loading files. Notes may retrigger; waveform, envelope and scheduler-phase continuity are not claimed. Parameter-only processing does not trigger the structural-resource check.

When audio has already entered the failed/manual-retry state, retry discards only stopped, rack-owned nodes and abandoned sampler documents before rebuilding the selected patch. It cancels stale requests/tail timers and clears note ownership; it does not delete or rewrite sound files. This prevents a missing source in an abandoned old graph from permanently blocking a different valid selected patch. Sampler controls retain the existing recovery policy; no input singleton is enumerated or attached.

When audio is stopped, patch selection remains available for repair. Layer and effect edits update the authored documents without instantiating instruments. Configuration/state-capture caches are invalidated so an old live AU cannot overwrite the new authored state during save. The next Start rebuilds the current document from a clean rack, including edits made after an earlier recovery failure. This is explicit offline editing, not a claim that an unavailable instrument is playable.

## Evidence

`ResourceAvailabilityTests` is in the default gate. It uses original generated WAV files, disposable managed presets and isolated setlist/settings data. Its production-graph render route is offline stereo 48 kHz with 512-frame blocks. Checks cover:

- Live patch rejection before selection/note/pedal/snapshot/session mutation, with continued resident audio.
- A missing reference at index 4,096 of a 4,097-entry synthetic reference map; managed directories rejected and a valid symlink accepted.
- Moving an active generated sample out of the expected path: a later structural edit rejects before stop/reload; earlier gain/pan changes roll back; graph generation, unit identity, held intent and saved bytes remain intact.
- Moving exactly the original bytes back: the same processing request succeeds and changes rendered level.
- Selecting a different valid patch after source loss: controlled failure followed by a fresh-rack retry renders the selected sound without requiring the abandoned source.
- Stopped navigation to an unavailable patch, document-only sound/effect repair, then a successful Start and rendered notes.

These are deterministic filesystem simulations, not tests of physical volume unplug, storage permissions on every platform, file-provider eviction or network-volume latency. The tests move only generated disposable files, not user/vendor content. The first broad regression run caught a plugin-editor request cancellation change; the original cancellation behavior was restored before final verification.

See [verification commands, results and frozen inputs](Completion/resource-recovery-verification.json). Earlier evidence records retain their original input sets.

Final local verification: **107 program outcomes: 96 passed, 11 explicit private-fixture skips, zero failures**. One reported pass remains the known private PianoHeldNoteTests early return; no piano qualification is inferred. Both unsigned release artifact gates passed, plus runner coverage/contract, distribution refusal/content, shell syntax and whitespace checks. All 202 frozen source/test/project hashes were unchanged after verification. C DSP sources were unchanged, so the earlier sanitizer result was not rerun.

## Remaining scope

Files can disappear or become unreadable after any preflight. Actual load/restore/restart errors still use graph rollback or the explicit stopped state. No periodic scanner, automatic relinker, rewritten reference paths or substitute samples were added. Unknown/relative/oversized preset inventories, arbitrary AU-managed resources, real device/storage contention, actual third-party plugin faults, physical mobile operation, long rehearsal and the real intermittent AVFAudio `-1` trigger remain qualification gaps. This work does not establish full compatibility or uninterrupted waveform recovery.

No GitHub issue changes/closure, commits, signing, install or distribution were performed.
