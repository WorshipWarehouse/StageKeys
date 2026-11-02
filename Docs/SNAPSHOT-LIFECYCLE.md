# Snapshot transition ownership and interruption

Implementation follow-up for #16/#123/#110, 2 November 2026. This extends [snapshot processing transactions](SNAPSHOT-PROCESSING-RECOVERY.md); it does not close the broader device/release qualification gates.

## Reproduced defect and behavior

A generated regression reproduced Stop Audio leaving the snapshot timer active: after Stop, layer gains/pan and performance controls continued moving toward the target. The baseline run fails at the assertion that the stopped document must remain unchanged. Stop now invalidates the transition before stopping audio and pins its last committed gain requests. Startup failure, engine-configuration recovery, patch reapplication and termination notification handling also cancel owned transitions. Background/focus loss alone keeps its existing performance behavior.

Transitions now carry a generation token, originating patch identity and ordered layer identities. Each tick checks those identities and its target selection before processing. An obsolete tick cannot modify a replacement document or clear a newer transition. On document/context mismatch it detaches its own timer without sending gain requests to the replacement document. Cancellation clears an incomplete target selection; a completed snapshot remains selected through Stop.

Elapsed fade time uses monotonic system uptime instead of wall-clock Date arithmetic. Fractions remain bounded, and nonfinite/negative authored timing is rejected before mutation. AU patch loading refuses snapshot recall until the patch is ready, preventing recall from changing documents underneath pending instrument installation.

Muted-to-live recall publishes its zero starting gain when unmuting, then progresses toward the requested target. Later frames continue to use the existing processing acceptance transaction. If processing rejects and already triggered another recovery generation, the old timer cannot cancel that newer owner. These changes retain prior successful frames rather than rewinding an entire partially completed performance transition. Live manual cancellation keeps the existing short gain smoothing; stopped/failure paths pin immediately.

## Evidence

`SnapshotLifecycleTests` is added to the default gate. It uses generated native sample fixtures, the production offline graph and bounded real run-loop waits. It verifies:

- Baseline failure: the document continues changing after Stop before the fix.
- Stop during a fade freezes layer documents, wheel/Tonic controls and explicitly saved session/settings bytes; the incomplete selection clears.
- Successful recall after restart, and retaining a fully completed selection across Stop.
- An offline engine stop plus a simulated configuration-change notification cancels the fade while the existing automatic restart still works.
- Replacing the patch at the same index or replacing a layer identity cannot receive old timer writes.
- A newer recall supersedes the previous transition, including after the old duration elapses.
- Muted initial gain is published correctly; NaN seconds and infinite beats are rejected without document changes.

`PatchReadinessTests` also checks that recall during a two-AU load leaves the pending layers and snapshot selection unchanged. Existing snapshot processing, snapshot slots, graph recovery, Store and CoreMIDI PlugAndPlay regressions remain in the default gate.

See [verification commands, outcomes and frozen inputs](Completion/snapshot-lifecycle-verification.json). The configuration test exercises notification/retry ownership on an offline route, not physical unplug, sleep/wake, interruption entitlements or measured hardware recovery latency. Prior records retain their own source input sets.

Final local verification: **111 program outcomes: 100 passed, 11 explicit private-fixture skips, zero failures**. One reported pass remains the known private PianoHeldNoteTests early return; it is not exercised piano evidence. Both unsigned release artifact gates passed, along with runner coverage/contract, distribution refusal/content, shell syntax and whitespace checks. All 206 frozen source/test/project hashes were unchanged after verification. C DSP sources were unchanged, so the earlier sanitizer result was not rerun.

## Remaining scope

No waveform/envelope/scheduler-phase continuity, latency improvement or rewind of emitted external MIDI is claimed. Direct arbitrary in-place changes that preserve all identities are not a general document transaction protocol; supported authoring paths still own their cancellation/commit policy. Explicit offline snapshot authoring, all manual controller-versus-fade ownership choices, real third-party state behavior, physical mobile/audio devices, long rehearsal and actual intermittent AVFAudio `-1` reproduction remain separate qualification work. The existing private piano early-return limitation remains unexercised without its fixture.

No GitHub issue changes/closure, commit/push, signing, installation or distribution were performed.

Subsequent work: [deliberate audio Stop](MANUAL-AUDIO-STOP.md) prevents MIDI/refresh/view lifecycle from restarting stopped playback and keeps failed audio on its explicit retry path.
