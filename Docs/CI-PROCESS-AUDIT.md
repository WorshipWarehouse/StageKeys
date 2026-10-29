# PR check process audit

The required checks cover different risks and remain unchanged: `builds (mac)`, `builds (simulator)`, `processing` and `library`. No branch protection, review requirement, content boundary or sanitizer gate is disabled. Check names remain unique; PRs run once and main verifies the landed commit on push.

## What is worthwhile

- Mac universal and mobile Release gates catch platform/compiler/resource differences, verify executable architecture and metadata, enforce library-free bundle contents and check the compiled mobile icon.
- Processing gates cover malformed/archive refusals, metadata, content provenance, calibration evidence and ASan/UBSan DSP behavior. These are distinct from compiling the app.
- Library regressions exercise production parser, persistence, sampler, MIDI and AU lifecycle code with portable generated fixtures. Private-source and physical-device qualification remain separate; missing fixtures must be visible.

## Waste removed

The latest successful main run before this integration was [40784732496](https://github.com/WorshipWarehouse/StageKeys/actions/runs/40784732496). Its library job took 2,084 seconds, compared with 151 seconds for Mac build, 204 for mobile build and 184 for processing. The shell runner recompiles the complete Swift core for every test. Expanded lists made this worse, and ten waiting PRs created a runner queue.

The CI library job now uses `Tests/run-local-library.py`: compile the full source list once with DEBUG/testable access, compile each unchanged test body against it, and execute every default Swift and native C program named by the existing shell gate. It starts from source on every run; no compiled-artifact cache, stale success status or omitted platform check is substituted. The original shell runner remains available as an independent monolithic/local fixture path. This changes compilation organization, not DSP assertions.

The integration retains the union of every waiting PR’s default list: 73 Swift entries and five C programs. Local combined run: **67 passed, 11 private-fixture skips, zero failures**. Per-program compile/execution times total 104.934 seconds locally (excluding shared-core setup); this is not a hosted speed claim. Both combined Release artifact gates passed. The new hosted run must independently satisfy all four required checks before merge.

## Trustworthy outcomes

The runner emits `results.json` and a GitHub step summary distinguishing pass/skip/fail. A skip has `passed: null`, its explicit reason and a separate count. Compile errors, nonzero/crashed tests, missing files and 300-second command timeouts fail the job and retain partial outcome evidence. A test printing SKIP and then crashing is a failure. Explicit EXS fixture arguments remain supported; fresh private test data directories are used for each invocation.

Six portable runner-contract tests check complete plans/source files, duplicate/incomplete plan rejection, skip classification, compile/runtime/timeout failures, nonzero command propagation and fixture arguments. They run in the processing job. Library outcome/summary artifacts are retained for 14 days without uploading generated audio, private libraries, plugin state or user setlists.

## Landing policy

The reviewed heads of #76/#77/#81/#83/#84/#86/#90/#91/#92/#93 are retained in this integration. Shared test-list conflicts are resolved by retaining the complete union; Store changes retain both explicit Program Change opt-in and stale AU-editor request cancellation. No unresolved review threads were present at inspection.

The old #81 auto-merge is paused to serialize landing. Once the new integration is published, redundant old runs may be cancelled and retained as cancelled, not represented as passing. Merge only the new exact head after local integration checks and the required hosted checks pass. Close the old PRs as incorporated/superseded after verifying their heads and resulting content, not because a related issue exists. Squash merging is acceptable: compare the landed tree with the verified head to establish content identity.

## Limits and follow-up

Do not infer physical iPad/AUv3, original-preset sonic parity, physical keyboard startup/latency, slow-storage budgets, signing/notarization or long live soaks from these checks. Those stay in the release issues. Keep nightly/private hardware runs explicit and separate. Future additions should include a deterministic failure reproduction and their runtime cost; avoid adding repeated full-core compilation, arbitrary fixed sleeps, silent skips or assertions that merely mirror implementation.

Exact PR heads, baseline job times and combined local outcomes are in `CI-PROCESS-AUDIT.json`.
