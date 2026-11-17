# Patch-wide instrument readiness

Implementation follow-up for #123/#110, 2 November 2026. This follows [snapshot processing recovery](SNAPSHOT-PROCESSING-RECOVERY.md).

## Performer behavior

Selecting a patch starts a generation-bound operation across its performance slots. AU patches have a gated asynchronous readiness window; native-only patches complete synchronously with their existing tail behavior. The engine may be running while the patch is still loading; the performance view and Audio Status explicitly show **Loading patch…**. Performance-slot output stays muted and screen/hardware/scheduled performance notes are gated until every slot reports completion. An AU completing first does not make a partial patch playable. Tonic has its existing independent slot/lifecycle.

The selected patch remains the user's requested patch. A rejected instrument, saved-state restore or reported processing change stops audio, clears speculative configuration ownership and exposes the existing manual-retry state. Retry rebuilds the selected patch. This also handles preparation/instantiation failures without a graph-failure report; previously those failures could leave the global UI reporting Running. The scalar error domain/code/slot are preserved rather than replaced by a wrapper error code.

Changing patches invalidates the old operation. Load callbacks must match the request, patch generation, patch identity and original layer before installing. Stop cancels pending configurations and prevents a late callback from starting or replacing audio. Successful completion restores the requested patch levels only after all slots are ready. Loading itself does not save or rewrite the authored setlist.

Native candidates now execute the same in-transaction preparation callback as AU candidates. The patch-loading mute is applied before graph restart, and native saved state is restored inside installation instead of as a separate post-install transaction. Post-install processing rejection propagates a failed completion instead of being reported as success. If rejection occurs inside an enclosing host graph batch, it is raised through that batch before stopped state is published, so a later outer restart cannot contradict the failed UI.

## Evidence and limits

`PatchReadinessTests` is in the default library gate. It uses isolated, original generated WAV samples and fully initialized offline Apple sampler candidates through the real asynchronous instantiate callback path. It checks out-of-order completion, awaiting all slots, gated screen notes, a muted ready slot, failed `-1` instantiation with unchanged saved bytes, manual retry with actual rendered sound, supersession, late callbacks after Stop, and synchronous post-routing rejection inside an enclosing patch batch followed by retry.

This is coordinated readiness and explicit failure recovery, not simultaneous all-or-nothing installation of every instrument. Individual units can be installed while the patch is muted. It does not keep the old patch playable during loading or restore its selection after failure. Existing reference-tail behavior is not a promise of uninterrupted old audio across the loading mute. Live third-party AU behavior, timeout/crash containment, external-device MIDI effects, scheduler/DSP history, phase-continuous held audio, hardware route/latency, physical mobile operation, long rehearsal and the real intermittent `-1` trigger remain unqualified. Existing plugin quarantine/explicit retry policy remains in force.

Final local verification: **106 program outcomes: 95 passed, 11 explicit private-fixture skips, zero failures**. One reported pass remains the known private PianoHeldNoteTests early return; it is not exercised piano evidence. Both unsigned release artifact gates passed, along with runner coverage/contract, distribution refusal/content, shell syntax and whitespace checks. All 201 frozen source/test/project hashes were unchanged after verification. C DSP sources were unchanged, so the prior sanitizer result was not rerun.

Commands, outcomes and frozen source hashes are in [the verification record](Completion/patch-readiness-verification.json). Prior records retain their own historical source sets and results. No GitHub writes/closure, commit/push, signing, installation or distribution were performed.

Subsequent work: [resource availability and stopped-mode repair](RESOURCE-RECOVERY.md) adds pre-selection checks, active-reference protection before structural reload, clean retry after abandoned-source loss and offline document repair. This record's original verification counts and inputs remain unchanged.

Subsequent work: [Audio Unit recovery settings](PLUGIN-RECOVERY-SETTINGS.md) exposes named blocks and per-instrument retry permission, with durable journal updates and explicit storage-failure handling.
