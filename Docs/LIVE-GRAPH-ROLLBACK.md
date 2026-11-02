# Live graph rollback and deferred AU commits

Implementation follow-up, 2 November 2026, for #123/#110. This extends the historical [graph-completion recovery](GRAPH-COMPLETION-RECOVERY.md) evidence. It does not close either issue or establish the cause of the reported intermittent AVFAudio `-1`.

## Implemented behavior

Before a structural edit, the rack retains its own node identities, per-output-bus connection points/formats, active voices, controller values, note intent, mixer settings, built-in effect parameters and bounded retired-tail records. It does not enumerate `AVAudioEngine.attachedNodes`, which can instantiate the input singleton. If the operation, sampler restoration or engine restart fails, it reconnects the retained graph and attempts restoration/restart. The original error still propagates; scalar support evidence separately records forward completion errors, rollback success and rollback error. A failed rollback leaves the engine stopped and uses the existing explicit manual-retry flow.

Note intent records pitch, velocity, source and key release under sustain. Sampler reloads replay owned notes, including note-on/note-off under the retained pedal. Pedal release, source release, Panic and replacement retirements clear the corresponding intent. Successful replacement does not inherit the retired sound's notes. Retriggering can be audible: no phase, sample-position, envelope, scheduler-time or uninterrupted release-tail continuity is claimed. DSP histories are not serialized by the parameter snapshot.

A whole-patch operation also changes host selection, MIDI and configuration caches. When such a batch rejects speculative configuration, it stops and requires saved-patch retry even if rack rollback succeeded. A rack-only failed batch whose prior graph is restored can remain running. This distinction prevents a restored old unit from being advertised under speculative host caches.

`commitLayer` now defers AU document, snapshot, MIDI and save changes until its asynchronous installation completes. Saved AU state is applied within candidate installation; rejection rolls back before success is published. Pending proposals are guarded by request, patch and original-layer identity. A newer edit/selection, audition, stop or failed graph invalidates them. A conflicting fader edit wins and discards the pending proposal. The library's editor-opening intent waits for successful commit and is consumed once; it never opens the previous instrument while a replacement is pending. Existing plugin failure-journal blocking remains in force; tests explicitly clear only their isolated generated journal between deliberate failures.

## Reproducible regression scope

`NativeGraphRollbackTests` uses original generated samples, a 48 kHz stereo offline route and 512-frame blocks. It covers six one-shot restart failures after replacement, repeated failures after a nested imported fan-out is connected, old unit identity, exact saved bytes, bounded tracked node/tail counts, rendered held/pedal notes, pedal/source release, successful changes on another channel, Panic, and explicit host-batch retry. Finite release/effect tails are allowed to decay before silence assertions.

`AudioUnitCommitTests` drives the real asynchronous completion path with generated Apple sampler candidates: pending and rejected installation, malformed state, an injected failure after the state setter, conflicting user edits, newer native selection, accepted state capture and deferred one-time editor intent. This does not simulate an arbitrary vendor's internal implementation, a setter exception, a process crash or out-of-process containment.

Existing graph failure, native decoder, tail, parallel routing, startup, Tonic, persistence, support-redaction and library tests remain in the default gate. Final commands, outcomes and frozen input hashes are in [the verification record](Completion/graph-rollback-verification.json). The private PianoHeldNoteTests early-return limitation remains: its pass status without the private fixture is not exercised piano evidence.

Final verification: **104 program outcomes: 93 passed, 11 explicit private-fixture skips, zero failures**. One pass status is the known private piano early return described above. Universal unsigned macOS and iOS Simulator Release artifact gates passed. Runner contract/coverage, distribution refusal/content, shell syntax and whitespace checks passed. All 199 frozen source/test/project hashes were unchanged after verification; C DSP sources were unchanged, so their prior sanitizer result was not rerun.

The first broad run caught an overly broad batch-stop policy in the unchanged SamplerStartupTests; the first platform builds caught an onChange overload newer than the deployment targets. Both were corrected before the complete final checks. Earlier test-development assertions were also refined to allow finite release tails and respect the existing generated-plugin quarantine/state-capture behavior; those exploratory runs are not final acceptance evidence.

## Remaining milestone acceptance

The following remain open; none is silently deferred or qualified by compilation:

- Full document/audio atomicity across snapshot morphs, arbitrary parameter mutations and multi-AU patch recall. Some existing callers still update the model before configuring processing, and processing errors are reported through callbacks. Rack structural rollback alone does not make those wider operations atomic.
- General rollback of arbitrary third-party internal state, imported MIDI scheduler time, DSP history, and continuous held/release waveforms. Candidate state-setting boundary faults are covered; real plugin faults/crash/hang behavior still needs qualification.
- Storage/source disappearance during an active edit. Recovery can itself fail if a retained sampler document no longer resolves; the controlled stopped path remains the fallback.
- Real occurrence of the intermittent `-1`, its triggering control and route; hardware MIDI/audio latency, contention/unplug/sleep, prolonged rehearsal/soak, physical iPhone/iPad, and real third-party AU coverage.

No GitHub issue has been edited or closed. No commit, signing, install or distribution action was performed. Existing audit and verification records remain historical snapshots of their own input sets.

Subsequent work: [snapshot and effect processing transactions](SNAPSHOT-PROCESSING-RECOVERY.md) addresses the supported processing-frame and effect-edit subset of the first remaining item. The original counts and source hashes above remain historical; broader configure callers and multi-AU instrument/patch recall still need work.
