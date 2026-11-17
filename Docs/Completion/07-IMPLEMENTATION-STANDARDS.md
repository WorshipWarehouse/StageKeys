# Implementation and verification standards

These standards govern subsequent approved work. They do not authorize implementation or GitHub publication from this research checkpoint. Follow root AGENTS.md and the committed Xcode project; preserve independent implementation and source/content boundaries.

## Select and scope work

1. Refresh checkout/remote issue state and record commit, working-tree changes and relevant decisions. Read the current issue, its discussions, this playbook and affected implementation/tests.
2. Select a ready roadmap task whose prerequisites are evidenced. Separate bug reproduction, compatibility hypothesis, qualification gap and proposed enhancement. Check duplicates before adding issues.
3. Define observable before/after behavior, ownership, formats, failure semantics and measurable acceptance. Resolve snapshot/cloud/routing scope decisions before dependent implementation. Prefer a targeted root-cause fix; architecture changes need justification and owner approval.
4. Use disposable data directories and original generated fixtures. Keep source/sample/plugin/user-state bytes out of public fixtures and logs. Preserve exact source bytes/hashes where import semantics require them.

## State, persistence and edit lifecycle

- Keep UI state, accepted document state and active audio state consistent through success and failure. A successful view update is not proof a graph change applied.
- Preview must state what is temporary. Cancel/Discard restores the draft's covered state; separately committed tag edits need an explicit contract. Guard stale callbacks by generation and identity after patch/layer/component replacement.
- Preserve stable IDs deliberately on recall/import; duplicate should create independent owned instances. Never erase legacy snapshot state to match a different reference contract without an approved versioned migration.
- Reject unknown/future/malformed/oversized data explicitly. Never autosave defaults over a failed load. Preserve validated backups and damaged bytes. Fault-inject prepare/write/commit/recovery boundaries; specify whether atomicity is per file or whole operation.
- Imported source routing/processor order/macros/MIDI not supported by the destination must stay archived with explicit omissions. Archive, partial translation and playable conversion are distinct statuses.

## Audio and MIDI

- No graph creation/teardown, file access, blocking lock, unbounded allocation or UI work on a render path. Audit taps/diagnostic callbacks as well as C render code, and record actual execution context before making real-time claims.
- Allocate buffers/DSP histories off callback, bound queues, establish single/multiple-producer ownership and explicit overflow behavior, and test stop/replacement lifetime. A bounded queue does not prove a bounded callback when it allocates or waits.
- Graph mutations must have a declared failure/commit strategy. A restart attempt, sampler restoration or retained tail is not general rollback. Test audibility and state after injected failure at every relevant phase.
- Preserve source/channel/note and pedal ownership, including repeated same-pitch notes. Disconnect releases only the affected source; Panic has explicit global/channel/tail scope. Preserve note-off semantics through transpose/mappings/tempo changes.
- Treat UI-run-loop MIDI FX scheduling as non-sample-accurate until measured and replaced/qualified. Record jitter under UI/plugin/storage load, not only deterministic fake-time tests.
- Define the actual meter/limiter point across all branches (click/tonic/external instruments/tails/routes). Preserve fixed source gain; do not hide conversion errors with gain riding or fixture-specific compensation.
- Plugin instantiation timeout is not process isolation. Record AU version/format/architecture, in/out-of-process policy, state restore threading, fault boundaries and actual tested components.

## Validation selection

| Change | Minimum focused validation | Additional release qualification |
| --- | --- | --- |
| Parser/converter | Generated valid/malformed/unsupported fixtures, original-byte hashes, missing/ambiguous identity and atomic cancel/failure | Authorized representative corpus; clean host without MainStage; relocation/restart |
| DSP/routing | Deterministic finite/silence/impulse/transfer/automation/block-size tests; sanitizer suite where affected | Matched reference path, listening and supported-device resource/latency checks |
| MIDI | Two-source/channel ownership, repeated pitch, pedal/release/Panic, loop/reconnect and persisted mappings | Physical boot/hot-plug and latency/jitter captures |
| Persistence | Legacy/future/corrupt/oversized/unsafe-file cases, round-trip, interrupted save and recovery | Clean-device restore, permission/disk constraints, user-visible recovery |
| AU hosting | Identity/generation/timeout/journal/state/editor tests | Real/fault AU matrix, route/sample rate/block/multi-output and physical AUv3 |
| UI/control | Model/control contract and real keyboard/VoiceOver/resize/preview-cancel checks | Physical touch/orientation/split/compact screen evidence |
| Build/resources | Applicable unsigned artifact gate and policy checks | Owner-authorized signing/notary/install/update/rollback; physical mobile |

Do not add mirror tests for trivial reversible prose/layout changes. Nontrivial parsing, DSP, migration, MIDI and persistence fixes require meaningful regressions. Run directly affected checks after the final edit; broaden only when interactions, failures or release scope justify it.

## Reproduction commands

```sh
python3 Tests/run-local-library.py . /private/tmp/stagekeys-next-task FocusedTestName
Tests/test-reverb.sh
python3 Tests/test-library-gate.py
Tools/verify-release.sh mac /private/tmp/stagekeys-next-mac
Tools/verify-release.sh simulator /private/tmp/stagekeys-next-simulator
```

Use fresh outside-checkout paths and the actual selected test name. The focused Python runner does not run default C tests; run the relevant C program/suite separately. The shell runner appends its default C loop even for selected Swift tests. Physical/private tests remain documented in LOCAL-VERIFICATION. Do not remove assertions or reinterpret skips as passes to make CI green. Preserve runner behavior, all four required CI jobs and complete failure/skip reporting.

## Evidence record and definition of done

Record actual command and exit, source SHA, platform/toolchain, fixture provenance, data isolation, pass/skip/failure counts, logs/hashes and unperformed checks. A measurement needs conditions and units; a reference comparison additionally needs reference version/license, source identity, MIDI/tempo, rate/block/route/gain/capture method and known alignment/processing differences. Never substitute a skipped private source for a synthetic equivalent while retaining the original equivalence claim.

A task is done only when approved intended behavior is implemented, every retained acceptance item is demonstrated or explicitly moved with owner approval, directly affected regressions pass, material integration/platform checks pass, limitations are updated, and a reviewer can reproduce the evidence. Green compilation and a merged PR are insufficient. No known regression means no known regression within the checks performed, not a universal guarantee.

## GitHub and release changes

At this checkpoint, all issue bodies/labels/milestones/new proposals remain local. Obtain the user's approval for the concrete proposed GitHub batch or implementation milestone. Preserve issue history/discussion, do not delete issues, and do not close broad gates because a narrow fix landed. Keep task state `needs-evidence` when implementation exists but qualification is missing.

Do not sign/upload/publish/deploy or mutate release infrastructure without explicit authorization. A later owner-authorized release uses the committed project, provenance checks, required notices and actual public artifact validation. Root StageKeys license remains unspecified unless the owner records a decision; no default MIT grant is inferred.
