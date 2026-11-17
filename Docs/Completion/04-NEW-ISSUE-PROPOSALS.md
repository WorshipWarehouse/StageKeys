# New issue proposals

These are local proposals, not published issues. Duplicate search covered all 51 StageKeys issue bodies/comments, 75 PR descriptions, RELEASE-ISSUES and prior reviews. Existing umbrella ownership is preserved. Prefer an amendment to the named parent when a separate issue adds no useful engineering boundary. No unsupported reference feature becomes a requirement by inference.

## N01 — Remove callback locks and per-buffer allocation from opt-in audio checks

- **Classification / priority / complexity:** real-time technical debt and validation gap; P0 before reliability qualification; M. No audible underrun reproduced.
- **Problem/current evidence:** `AudioController.installOutputTap` calls `AudioDiagnosticRecorder.append`; that method locks an NSLock, allocates AVAudioPCMBuffer and submits an async closure for each accepted buffer. Writes happen in the background but callback work is not allocation/lock free. `pending < 32` bounds queued buffers, not lock wait or allocation time.
- **Expected behavior:** user-controlled capture preserves exact stereo samples and duration without blocking an audio callback or creating unbounded work. On overflow, report incomplete capture rather than silently drop samples.
- **Duplicate/owner:** #4 covers real-time budgets, #23 diagnostics, #123 operation recovery; none isolates this recorder transport. Link a focused child of #4; do not duplicate the whole diagnostics feature.
- **Root cause:** confirmed call-path structure; tap thread scheduling and actual deadline impact require measurement.
- **Requirements/ordered plan:** (1) profile callback thread/allocations with recording off/on; (2) define capacity and overflow semantics; (3) prepare bounded reusable buffers/control state off callback; (4) hand off bounded records without callback waits, retain writer lifecycle ownership; (5) verify stop/concurrent overflow/file failure/restart and exact frame identity. Choose queue design from measured thread/producer contract, not an assumed lock-free recipe.
- **Dependencies:** existing recorder tests; #123 diagnostics fields must not introduce more callback work. Can proceed beside graph research with isolated files.
- **Acceptance:** [ ] documented callback allocation/wait audit; [ ] no new buffer allocation or mutex wait in recorder append on tap path; [ ] exact stereo/duration retained; [ ] overflow is visible and safely terminates an incomplete take; [ ] bounded memory and repeated start/stop; [ ] measured disabled/enabled worst-case time on declared hardware.
- **Validation / done:** AudioDiagnosticRecorderTests and new capacity/fault/concurrency regressions; Instruments allocation/lock traces and hardware playback capture. Preserve current finite-duration/privacy contract. Evidence must distinguish tap callback from the main C render callback.

## N02 — Define and test output headroom after metronome summation

- **Classification / priority / complexity:** audio test gap with potential peak-protection defect; P0 qualification; S investigation, M if graph change required.
- **Problem/current evidence:** `AudioController.init` connects mainMixerNode → outputLimiter → protectedOutput and metronomeNode → protectedOutput. The 1 dB protectedOutput attenuation applies to the sum; the click is outside the limiter. No combined-output peak bound is established by that topology alone.
- **Expected behavior:** declared output ceiling/overload reporting includes every audible branch at the actual output. Preserve master-follow choice, click routing and sound, and disclose any intended independent click protection.
- **Duplicate/owner:** focused child of #3, linked #108 (closed metronome software) and #107 future routing. Do not reopen #108 for unrelated control work.
- **Root cause:** bypass path confirmed; actual overload/clipping is unmeasured, so do not label it a reproduced audio defect.
- **Requirements/ordered plan:** (1) render maximum configured click with dense sustained layers, FX tails and master variations; (2) quantify post-sum sample peaks and compare declared ceiling; (3) decide common post-sum protection versus bounded independent click; (4) change only if required; (5) retain meter tap after every protected branch.
- **Dependencies:** #3 output policy; coordinate #107 routing contract. No reference-app matching required.
- **Acceptance:** [ ] deterministic click-plus-mix impulse/dense-note tests at 44.1/48/96 kHz; [ ] zero/master-follow-off/on cases explicit; [ ] measured output within approved ceiling or intentional behavior documented; [ ] meter includes all branches; [ ] no gain-riding or change to converted source levels; [ ] no doubled clicks/start-retry paths.
- **Validation / done:** OutputMeterTests, MetronomeTests, MetronomeSettingsTests and a production AudioController offline summation regression; real output trace before release. A code topology reading alone cannot close it.

## N03 — Persist resumable conversion checkpoints without losing transaction ownership

- **Classification / priority / complexity:** residual requirement from closed #8; P1 unless owner includes bulk-resume in v1; L.
- **Problem/current evidence:** #8's last comments explicitly leave persisted checkpoint/whole-concert resume open despite CLOSED state. SoundLibrary nonblocking ownership lock and compare-before-commit already exist; duplicate retry is not a persisted checkpoint. MAINSTAGE-IMPORT-MILESTONES records this gap.
- **Expected behavior:** resume only a declared-supported batch after process interruption, with source/asset identity checks, no duplicate personal-edit overwrite and no partial catalog corruption.
- **Duplicate/owner:** recover #8 residual acceptance by approved reopen or this linked child, never both. #5/#6 own interpretation and topology, not checkpoint durability. N04 supplies batch source enumeration if included.
- **Requirements/ordered plan:** define checkpoint schema/provenance/ownership; stage generated batch assets with explicit cleanup ownership; persist phase boundaries; reject changed source/hash or incompatible version; reacquire catalog lock and revalidate before one commit; expose resume/discard and bounded cleanup. Never delete user assets using a stale checkpoint.
- **Dependencies:** #20 migration/recovery contract; existing #104 cross-process lock; N04 for folder/concert resume integration. Can design schema while importer support is fixed, but integration follows source enumeration.
- **Acceptance:** [ ] interrupted prepare/commit/relaunch matrix; [ ] unchanged catalog on cancelled/failed operation; [ ] exact source hashes; [ ] competing writer/recovery refusal; [ ] versioned checkpoint validation; [ ] personal tags/ratings retained; [ ] bounded orphan cleanup with no private payload committed.
- **Validation / done:** TransactionalImportTests plus subprocess-kill/restart generated batch fixtures; clean-host relocation/restart playback, preserving stricter all-or-nothing API and explicit supported-subset UI semantics. Owner first decides whether this remains required after #8 closure.

## N04 — Retain whole-concert/folder and multi-instrument import scope from closed #85

- **Classification / priority / complexity:** compatibility/missing requirement; P1 scope decision; L–XL (split after topology contract).
- **Problem/current evidence:** #85's final comment leaves whole-concert/folder selection and multi-instrument decomposition; current MAINSTAGE-COMPATIBILITY-MATRIX explicitly rejects multiple sampler instruments in one channel. Single patch/CST discovery and scoped bookmarks already work.
- **Expected behavior:** bounded batch enumeration and honest per-channel outcomes. A multi-instrument channel may become playable only if shared gain/nonlinear processing/routing semantics are representable; separate layers are not presumed equivalent.
- **Duplicate/owner:** reopen #85 after approval or create linked retained-scope child. #6 owns actual topology/processor translation, #7 engine modes, #5 Locate/preflight, N03 checkpoints. Do not reimplement those systems here.
- **Requirements/ordered plan:** establish concert/folder format subset and enumeration limits; reject unsafe/malformed containers; inventory dependencies/identities; show preview/cancel and supported subset; integrate existing discovery/transaction APIs; add multi-instrument support only after #6 graph semantics, otherwise retain archive/explicit unsupported outcome.
- **Dependencies:** #5/#6/#7/#20; N03 for durable resume only. Batch UI can proceed after support contract while topology stays explicitly unsupported.
- **Acceptance:** [ ] generated nested folder/concert cases and bounds; [ ] every channel has outcome; [ ] ambiguous/missing references explainable; [ ] no double-import/shared-asset deletion; [ ] cancel/rollback preserve catalog/user edits; [ ] no flattening shared nonlinear paths; [ ] source/sample bytes unchanged; [ ] clean-host supported playback evidence.
- **Validation / done:** MainStageGuidedImportTests, MainStagePreflightTests, MainStageLayerAssemblyTests and new generated batch/topology fixtures; authorized representative sources remain private. Owner may explicitly defer this scope for first Mac release.

## Optional N05 — Support musical time signatures beyond the current 4/4 policy

**Proposed enhancement**, P2/L, owner approval required; not a demonstrated bug. Toolbar and Tempo sheet explicitly show 4/4. MetronomeSettings has beatsPerBar for accent grouping and Settings explicitly says it is not the performance time signature. A non-4/4 feature needs an approved numerator/denominator/beat-unit contract shared by patch tempo, metronome and MIDI FX. Related #108/#111; no existing issue clearly requests the full model. Acceptance, if approved: save/reload/migrate 3/4, 6/8 and irregular meter; preserve absolute tempo interpretation and click/FX phase; display actual meter consistently; generated long-run/tempo-change tests and musician review. Do not simply replace the label with beatsPerBar/4.

## N06 — Report missing private held-note fixtures as skips

- **Classification / priority / complexity:** test-reporting defect; P1/S, child of #22 or amendment to the maintained regression gate; duplicate search found no specific existing owner beyond #22/#82 infrastructure.
- **Evidence:** `Tests/PianoHeldNoteTests.swift` returns immediately if STAGEKEYS_PIANO_PRESET is absent. `run-local-library.py` classifies only output lines starting with SKIP as skipped. This session therefore reports this non-executed body as passed. The directly observed outcome is a reporting error, not a piano playback defect.
- **Expected / plan:** emit the standard explicit fixture skip, keep every audio assertion unchanged, add a runner/fixture contract test, re-run the missing-fixture case and an authorized fixture-present case when available. Never make private content mandatory in public CI.
- **Dependencies:** existing runner result schema; can proceed independently of DSP/graph changes. No change to #1 compatibility status follows automatically.
- **Acceptance / validation / done:** [ ] absent fixture records skipped with passed null and a reason; [ ] actual fixture path exercises all existing assertions or reports a genuine failure; [ ] runner tests protect the distinction; [ ] no private bytes committed; [ ] default suite remains transparent. Expected program totals after this reporting-only fix would change, but those future totals must be measured rather than substituted into this session's actual 88/11/0 record.

## Items that should stay in existing issues

Snapshot semantics and backward compatibility → #16 (decision D01); main-thread MIDI scheduling → #111/#4; imported signal order → #112; iOS interruption handling → #113; AU crash containment → #13; migrations/undo → #20; licensing/provenance → #64/#21; VoiceOver/compact layout → #19. No duplicate new tickets proposed for these. Cloud #121 and AI #24 remain independent proposals, not essential release gaps.
