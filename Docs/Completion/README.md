> License update, 4 November 2026: the owner selected MIT for StageKeys-authored code/documentation. See [the decision record](../PROJECT-LICENSE.md). References below and in the dated audit package to an unspecified root license describe the earlier audit snapshot, not current licensing. Broader provenance and public distribution remain unqualified.

# StageKeys completion playbook

Research/review checkpoint, **2 November 2026**. Source baseline `6a253130196e8beca471a575a45c1834d52cedf8` matched remote main. This package changes documentation only. It prepares concrete local issue drafts and a dependency-aware plan; it does not implement features, publish issue edits, close issues, sign or distribute an app.

StageKeys has a working independent performance and import foundation with strong synthetic regression infrastructure. Public live-performance reliability, full reference fidelity, broad source/plugin compatibility, physical mobile operation and signed distribution remain unqualified. The safest first engineering milestone is failure-safe live graph changes (#123), backed by the existing startup recovery and tail work.

## Read in this order

1. [Current-state audit and feature inventory](01-CURRENT-STATE-AUDIT.md)
2. [Reference behavior matrix and bounded continuation sessions](02-REFERENCE-BEHAVIOR-MATRIX.md)
3. [All existing issue audit and organization proposal](03-EXISTING-ISSUE-AUDIT.md)
4. [New issue proposals and duplicate decisions](04-NEW-ISSUE-PROPOSALS.md)
5. [Prioritized master roadmap](05-MASTER-ROADMAP.md)
6. [Dependency map and parallel work boundaries](06-DEPENDENCY-MAP.md)
7. [Implementation, testing and completion standards](07-IMPLEMENTATION-STANDARDS.md)

Supporting records: [all 35 open-issue description drafts](ISSUE-DRAFTS.md), [evidence and commands](EVIDENCE.md), [machine-readable verification](verification.json), [issue/PR inventory](github-inventory.json), and [file inventory/coverage limits](evidence-inventory.json). Raw private/local tool output remains outside source control. None of these records replaces the original GitHub discussion.

Current verification: unsigned universal Mac and iOS Simulator artifact gates pass; all nine Python checks and the 21-program DSP sanitizer suite pass. The default library runner reports **88 passed, 11 skipped, 0 failed across 99 programs**. One of those pass statuses is a known early return without its private piano fixture (N06); it is not exercised piano evidence. See EVIDENCE.md for initial environment failures and exact limits.

## Review checkpoint

| Requested checkpoint | Finding / concrete proposal |
| --- | --- |
| Actual condition | Substantial implemented app; release acceptance incomplete; current code supersedes many historical gap descriptions |
| Verified strengths | Blank/sample-free startup, synthetic conversion/playback, ownership/persistence guards, visible-effect selection, library transactions, tail bounds, tempo/key logic and automated artifact gates |
| Major gaps | General live graph rollback, measured callback/resource/latency bounds, complete migration/restore evidence, real AU/device qualification, missing multi-output/preload and source topology |
| Reference findings | Installed 2.5.2 metadata/static REA identity verified; live UI attempt timed out; prior Demo observations and manuals remain DOCUMENTED; no new sonic comparison |
| Existing issue audit | All 51 issues, including discussions, reviewed; 35 open/16 closed. #8/#85 residual scope needs reconciliation; #87 explicitly moved physical gates to #105 |
| Proposed issue updates | Append reviewed current-state enrichment from ISSUE-DRAFTS; preserve original criteria/discussion. No issue publication yet |
| New proposals | N01 callback capture transport; N02 combined click/mix protection; N03/N04 retained conversion-resume/batch scope; N06 truthful private-fixture skip reporting; optional N05 non-4/4 enhancement |
| Priority | Baseline/decisions → reproduce #123 → atomic live changes → AU and persistence contracts → hardware/content qualification → soak/beta → release |
| Critical dependencies | Snapshot decision before migration; graph safety before routing/preload; topology before faithful DSP comparison; physical gates separate from simulator |
| Release risks | Unexplained graph errors, callback locks/allocations, combined output ceiling, incomplete source/plugin/device evidence, unspecified root license and public distribution qualification |
| Owner unknowns | D01 snapshot semantics; D02 cloud scope; D03 routing/preload/batch v1 scope; D04 devices/budgets/tolerances; D05 closed residual issues; #64 license decision |
| First implementation milestone | Roadmap 02–04: qualify startup recovery, reproduce live graph failure, implement bounded atomic recovery with actual rendered continuity and state evidence |

## Product requirements and source precedence

Root AGENTS/README and owner instructions define independent StageKeys scope, sample-free distribution and authorized content boundaries. PUBLIC-RELEASE-CHECKLIST supplies release criteria, not completion evidence. MAINSTAGE-COMPATIBILITY-MATRIX defines supported subset policy. Current code/tests plus dated reproductions establish actual behavior. PARITY-STATUS, CHANGELOG, prior audits/calibrations and issue comments retain historical observations and limitations. First-party manuals are documented requirements/reference, not a successful observation of the installed build.

Resolve contradictions against actual artifacts and owner decisions; never count model agreement, UI resemblance or an upstream MIT processor test as Sunday Keys sonic equivalence. Keep archive/partial/playable statuses distinct. Cloud/Prime was historically excluded; #121 is an independent scope proposal requiring reconciliation. No public root license is inferred from component notices or #64's closed status.

## Release readiness

For the selected advertised platforms, all applicable P0 gates need reproducible evidence and P1 scope must be completed or explicitly excluded. No known unexplained clicks, silence, extra/stuck notes, data loss or unsupported silent substitutions. Supported imports survive save/restart/relocation. Supported rigs pass measured latency/headroom/recovery and prolonged rehearsal/soak. Plugin limits, physical mobile status, content provenance, licensing, signing/install/update/rollback and support guidance are explicit. Unsigned CI artifacts and simulator builds alone cannot qualify a public release.

## Progress tracking and next session

Keep task IDs 00–24 stable. For each approved task append date, implementation SHA, state (`ready`, `in-progress`, `needs-evidence`, `verified`, `deferred`), prerequisite evidence, acceptance results, logs, skip reasons and remaining limitations. Update issue/feature inventory and dependency edges together. Record owner scope decisions before changing acceptance; never edit old measurements to fit a new result. Refresh GitHub snapshot before publication and preserve the previous snapshot date.

Next action: review this package, record D01–D05 and the license decision, then approve a bounded implementation milestone and/or the exact issue-update batch. No feature work or GitHub changes begin automatically. Physical iPad work remains deferred under #105 until explicitly resumed.

## Approved implementation follow-up — 2 November 2026

The owner approved the first milestone and requested continued work. The historical audit above remains bound to its original baseline. Current source changes are recorded separately in [live sound-change preparation and diagnostics](../LIVE-CHANGE-RECOVERY.md) and [implementation verification](live-change-verification.json). The first bounded task-03/04 result protects preparation rejection before any graph/document mutation and adds privacy-safe failure context. This is not completion of the full graph rollback milestone or closure of #123. Post-attachment/state/restore/restart failures and the actual intermittent user -1 trigger remain the next investigation. GitHub issues remain unchanged; no distribution action is authorized.

The next approved fix is recorded in [native load rejection and pending-AU ownership](../NATIVE-LOAD-RECOVERY.md). Native decoder failures now retain the playing instrument and unchanged saved layer/snapshots, with same-identity retry. Pending/failed AU editor/state capture is identity guarded. See [separate final verification](native-load-verification.json); the original audit and first-fix verification remain historical snapshots. General post-mutation rollback and actual live -1 qualification are still outstanding.

The subsequent [graph completion recovery](../GRAPH-COMPLETION-RECOVERY.md) separates original/cleanup errors and adds a visible stopped/manual-retry path, including direct Tonic loads. [Verification](graph-completion-verification.json) retains its own final input set. Task 03/04 progress does not close seamless post-mutation rollback, held-note continuity, or real live -1 qualification.

The current [rack rollback and deferred AU commits](../LIVE-GRAPH-ROLLBACK.md) add retained routing/voice restoration, native note-intent replay and delayed AU layer persistence. [Its verification](graph-rollback-verification.json) records a separate input set. The remaining-acceptance list explicitly includes snapshot/parameter/multi-AU document atomicity and real hardware/plugin qualification; #123/#110 are not closed.

[Snapshot/effect processing transactions](../SNAPSHOT-PROCESSING-RECOVERY.md) now gate supported multi-layer processing frames and effect-document updates on audio acceptance. The [separate verification record](snapshot-processing-verification.json) preserves its own input set. Multi-AU instrument/patch selection and the remaining hardware/plugin/release gates are still open.

[Patch-wide readiness](../PATCH-READINESS.md) now gates performance-slot output and notes until all selected instruments finish, with generation-bound cancellation and stopped/manual-retry behavior on rejection. This is coordinated readiness rather than simultaneous multi-instrument installation or old-patch continuity. Its [verification record](patch-readiness-verification.json) is separate from earlier results.

[Resource recovery and offline repair](../RESOURCE-RECOVERY.md) now preflight live patch resources before selection changes, reject structural reloads of known missing active samples before engine stop, and rebuild abandoned graphs on retry. Stopped users can repair unavailable layer/effect documents without loading them. [Verification](resource-recovery-verification.json) preserves its own inputs; physical storage behavior and unknown reference formats remain unqualified.

[Audio Unit recovery settings](../PLUGIN-RECOVERY-SETTINGS.md) expose blocked instruments and selective retry permission without starting audio or unblocking others. Journal updates publish only after successful persistence and fail closed on write errors. Its [verification](plugin-recovery-settings-verification.json) retains a separate input set; actual vendor/plugin/platform qualification remains open.

[Missing Audio Unit availability](../MISSING-AUDIO-UNITS.md) now checks the fresh device catalog before loading, avoids quarantining absent components, preserves unavailable presets/state, and exposes repair guidance in the library and Audio Settings. [Verification](missing-audio-units-verification.json) keeps a separate input set; real registry/device/plugin qualification remains open.

[Operation-scoped AU catalog observations](../AU-CATALOG-OPERATIONS.md) now share one lazy registry observation across synchronous patch preparation/load requests and discard it afterward. [Verification](au-catalog-operations-verification.json) measures provider-call counts and freshness, not wall-clock latency or vendor qualification.

[Snapshot transition lifecycle](../SNAPSHOT-LIFECYCLE.md) fixes the reproduced post-Stop timer mutation, binds ticks to patch/layer/generation ownership, uses monotonic timing and gates recall during AU patch loading. [Verification](snapshot-lifecycle-verification.json) includes a failing baseline and simulated offline configuration recovery; physical-device recovery remains unqualified.

[Deliberate Stop and automatic startup](../MANUAL-AUDIO-STOP.md) fixes the reproduced virtual-MIDI wake after Stop, preserves monitoring/configuration, and separates automatic view startup from explicit resume. [Verification](manual-audio-stop-verification.json) also covers initial MIDI activation and failure-state retry ownership; physical-device behavior remains unqualified.

[Startup/loading Stop controls](../AUDIO-OPERATION-CANCEL.md) expose cancellation directly in the performance banner and Audio Settings, with deterministic retry-scheduler and late-AU callback checks. [Verification](audio-operation-cancel-verification.json) remains separate; logical cancellation does not claim preemption of a blocked vendor/native call.

[Bounded AU load admission](../AU-LOAD-ADMISSION.md) caps unresolved backend instantiation requests process-wide, retains their ownership through cancellation/timeouts/recovery, and provides capacity feedback without quarantining rejected submissions. [Verification](au-load-admission-verification.json) includes a failing baseline and generated callback/resource recovery cases; real vendor resource/process qualification remains open.

Follow-up: [audition resource preflight](../AUDITION-RESOURCE-PREFLIGHT.md) records known-resource rejection before editor/performance changes and its focused verification.
