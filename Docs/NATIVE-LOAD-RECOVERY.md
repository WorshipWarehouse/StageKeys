# Retain the playing instrument on rejected native loads — #123

Follow-up to [sound-change preparation](LIVE-CHANGE-RECOVERY.md), 2 November 2026. This completes the next bounded failure case, not the general graph rollback milestone.

## Reproduction and independent fix

A managed `.wav` can exist and pass preparation but still be undecodable. An original generated file containing malformed RIFF data reproduced that case. With the first preparation fix already applied, `NativeLoadFailureTests` failed at **Decoder failure after preflight must retain the original document layer**. The original audio controller still removed the old voice before invoking the loader, updated its identity cache before success, and removed the channel again on failure.

`AudioController.configure` now keeps the previous instrument and active control/identity cache until the loader succeeds. It no longer removes the playing voice before a replacement load, nor removes it merely because a candidate fails. Successful loading applies the new controls and forces the effect settings onto the newly installed voice. A failed identity is not cached as loaded, so the same sound can be retried after its generated file is repaired.

For native sounds, `PerformanceStore.commitLayer` now asks the synchronous loader to accept the candidate before modifying the document, snapshots, note ownership or saved session. A preparation or decoder rejection therefore leaves those states untouched. `configure` returns false for a synchronous preparation/loading rejection; true means accepted, including a pending asynchronous AU, and must not be interpreted as a general state/effect/graph transaction guarantee.

The loader already prepares a native single-file sample before attaching it, and configures sampler presets before retiring the old voice. This change uses that ownership boundary; it does not claim that every later restoration/restart failure rolls back. For the malformed-WAV scenario the graph generation and exact instrument object remain unchanged and the held sample continues rendering at its prior level.

## Pending AU ownership and editor/state guards

Keeping the previous voice means a channel can contain an old playing instrument while a new AU is pending. Every controller configuration supersedes the previous request and invalidates the rack's pending load generation without removing the playing voice. Late instantiation results cannot install after a return to the original sound or to an empty slot.

Editors and state capture now require the controller's requested sound identity to match a ready active instrument. They wait while a replacement is pending and do not use the old instrument just because the rack contains one. Failed reloads of the same AU component but a different saved state remain unavailable for editor/state capture until an explicit revert or successful retry. This prevents autosave, audition confirmation, library export and editor dismissal from writing the wrong instrument's state into the new AU document. Existing saved AU state is preserved when no matching ready unit exists.

These are safeguards around the existing asynchronous AU workflow. `Store.commitLayer` still commits AU document selection under its existing asynchronous contract; it does not provide the same synchronous document transaction as native sounds. Real plugin instantiation/state/editor compatibility, hangs and fault isolation remain #12/#13/#53 qualification work.

## Evidence and validation

The new default-gated `NativeLoadFailureTests` verifies:

- a real decoder rejection after preparation succeeds, using generated malformed WAV bytes;
- unchanged native document layer, snapshots and saved session bytes;
- retained instrument identity, graph generation, sustain and held-note output;
- direct controller rejection and corrected-file retry using the exact failed sound identity;
- deferred AU callbacks cancelled by reverting to a native sound or clearing an already-empty slot;
- a synthetic AU instantiate failure result leaving the previous native voice usable;
- a pending editor receiving no previous instrument, and state capture/library export preserving the requested AU's existing serialized state;
- a failed same-component/different-state AU reload remaining unavailable until an explicit revert.

The AU tests inject only instantiation callbacks and use Apple sampler objects and generated state. They do not establish third-party AU behavior or process isolation. No vendor assets, installed user sessions or private plugin state are changed.

Final verification: **101 program outcomes: 90 passed, 11 explicit private-fixture skips, zero failures**. The previously documented private piano test still returns early without a SKIP marker and remains included in the runner’s pass count; no private piano qualification is inferred. Both unsigned universal Mac and iOS Simulator Release artifact gates passed. Runner coverage/contract, distribution refusal, shell syntax and whitespace checks passed. DSP source did not change, so the earlier sanitizer suite was not repeated.

Commands, final input hashes and results: [native-load verification](Completion/native-load-verification.json). The first reproduction and intermediate checks are retained separately from the final frozen-source verification. An intermediate full run was invalidated by subsequent identity-guard edits and is not evidence for the final source.

## Explicit remaining boundaries

- Malformed WAV rejection occurs before live graph mutation. Sampler-preset decoding after candidate attachment, graph completion, sampler restoration, engine restart and source disappearance between checks still need dedicated failure tests and a staged commit/controlled recovery design.
- Native imported-processing and AU-state errors can still be reported after an instrument is installed. The acceptance boolean does not certify those phases; it is not a complete native patch transaction.
- `previousSoundRetained` records instrument/cache retention without a graph edit, not document rollback or uninterrupted audio for every caller. User messages no longer infer saved-document retention from that controller-only flag.
- AU document selection is still asynchronous. Editor/state capture is guarded, but complete AU document/audio commit or rollback is not implemented here.
- The user's intermittent live AVFAudio `-1`, AudioBox contention/unplug/sleep behavior, physical MIDI/mobile rigs and prolonged live soak have not been reproduced by this synthetic test.

Next failure boundary: candidate attachment/configuration and graph finish failures, including recording both an original operation error and any cleanup/restart error without silently losing one. #123 remains open; no GitHub mutation, signing, installation or distribution occurred.

A [graph completion follow-up](GRAPH-COMPLETION-RECOVERY.md) now records original plus cleanup errors and provides a truthful stopped/manual-retry state when restoration or restart fails. It verifies rejected candidate attachment and explicit saved-patch recovery; full seamless rollback and held-note continuity remain unqualified.

Subsequent work: [rack rollback and deferred AU document commits](LIVE-GRAPH-ROLLBACK.md). The outcomes above describe this record's original input set; consult the later record for current scope and remaining acceptance.
