# Graph completion failure and manual recovery — #123

Follow-up to [native load recovery](NATIVE-LOAD-RECOVERY.md), 2 November 2026. This change adds deterministic candidate-attachment/restoration/restart failure evidence and controlled recovery. It is not a seamless graph rollback implementation or a reproduction of the user's intermittent live AVFAudio `-1`.

## Reproduced defects

The previous rack implementation used `try? finishGraphChanges()` when the original operation threw. If candidate setup failed and the subsequent engine restart also failed, the restart error disappeared behind the original error. Separately, the store could retain `started == true` / Running even though the engine was stopped, making its normal Start action ineffective.

With debug-only faults for candidate attachment and restart, `GraphCompletionFailureTests` failed against the preceding working tree at **A graph cleanup failure must not leave the UI reporting Running**. The test uses generated session/sample content; injected error numbers 701–707 are test values, not observed Apple fault codes.

## Implemented behavior

- An outer graph transaction captures its original operation error and its sampler-restoration/restart errors separately. It still rethrows the original error type when present; callers' typed catch behavior is preserved.
- If sampler restoration fails, the graph is left stopped and restart is not attempted. A throwing engine start is explicitly stopped rather than treated as partially running.
- A scalar `AudioGraphFailure` record retains a random record ID, graph generation, whether a graph edit occurred, previous/current running flags, and separate numeric/error-domain summaries for the operation, restoration and restart phases. Unattempted phases stay absent.
- The controller exposes a completion failure that stopped previously running audio through one recovery notification. It invalidates active configuration caches and supersedes pending AU loads, so manual retry cannot mistake a partially installed candidate for the saved sound or accept a stale callback.
- The store enters a visible failed state, enables the existing Retry Audio / Audio Settings workflow, cancels scheduled automatic starts and transitions, and clears active note/pedal ownership and audio histories. There is no automatic retry loop for this failure class.
- Saved patch/layer/snapshot/session data is not replaced by a rejected native sound change. Runtime Tonic selection/power/key and metronome choice are retained. A successful explicit retry reapplies the saved patch and resumes the selected pad/click policy; previously held keyboard notes require fresh input rather than being unexpectedly replayed.
- The Tonic picker, which loads through the rack directly, uses the same recovery reporting. It does not recursively restore another pad into a graph whose completion has failed or erase the prior selection in that stopped state. AU audition state-restoration failures also reach the controller's graph recovery path.

No raw NSError description, arbitrary domain text, filename, device ID, plugin state or sample payload is retained in the diagnostic record. This optional record round-trips inside the existing local support report. It describes the last graph failure; it is not proof of a complete cross-request transaction trace. No automatic upload or disk diagnostic journal is introduced.

## Deterministic coverage

`GraphCompletionFailureTests`, in the default library gate, checks:

1. Candidate attachment fails and restart also fails: both errors remain available; the old native document and exact setlist/settings bytes remain intact; UI state matches the stopped engine.
2. Manual retry rebuilds saved instruments instead of trusting stale caches, then renders fresh notes with the pad/click isolated from that measurement. Pad note ownership and the click policy resume separately.
3. Sampler restoration fails after a candidate is installed: the partially restored graph is not restarted; the saved document survives and explicit retry reloads it.
4. A typed operation error plus cleanup restart failure preserves the typed catch and records the secondary failure.
5. Candidate attachment fails but completion succeeds: the original instrument remains available for fresh notes. This does not assert phase-continuous held-note recovery.
6. The Tonic picker's direct rack-load path enters the same failed state, keeps its previous selected pad/key and clears its loading state, then recovers on successful manual retry.
7. Support JSON preserves the nested scalar evidence without generated private description text.

Final local verification: **102 program outcomes: 91 passed, 11 explicit private-fixture skips, zero failures**. One pass status remains the known private PianoHeldNoteTests early return; no private-piano qualification is inferred. Universal unsigned Mac and iOS Simulator Release artifact gates passed. Runner coverage/contract, distribution refusal, shell syntax and whitespace checks passed. All frozen source/test hashes were unchanged after the checks. DSP C sources were unchanged, so the prior sanitizer suite was not repeated.

The fault hooks and candidate/note inspection helpers are DEBUG-only. They run the actual rack transaction and store state paths; they do not crash a real plugin or change installed user content. See [verification and input hashes](Completion/graph-completion-verification.json) for final commands/results. Historical first-fix/native-load verification records remain unchanged.

## Remaining milestone scope

Controlled stopping and explicit retry protect state when graph completion fails; they do not keep unrelated layers audible during an unrecoverable completion failure. A candidate-attachment failure whose cleanup succeeds can still interrupt/reinitialize held sampler voices. The tests establish fresh-note recovery, not uninterrupted waveform or pedal-held release-tail continuity.

Full staging/rollback for arbitrary imported effect/topology changes, AU document/audio commit consistency, plugin state-restoration faults, real third-party crash/hang containment, source/storage disappearance, physical route/latency and prolonged live rehearsal remain separate gates. Initial engine-start failures still use the existing startup policy; that broader live device behavior is not qualified by these graph injections. A real occurrence of the user's intermittent `-1` with its triggering control and audio route still needs capture. #123 remains open.

Subsequent work: [rack rollback and deferred AU document commits](LIVE-GRAPH-ROLLBACK.md). The outcomes above describe this record's original input set; consult the later record for current scope and remaining acceptance.
