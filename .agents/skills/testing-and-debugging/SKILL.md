---
name: testing-and-debugging
description: "Reproduce StageKeys defects and choose actual core, parser, DSP, audio and integration checks with honest outcomes."
---

# Testing And Debugging

Read `Docs/RELEASE-CI.md`, `.github/workflows/distribution.yml`, `Tests/test-library.sh` and `Tests/run-local-library.py` before choosing checks. Tests are standalone Swift/C programs, not necessarily an XCTest scheme. The runner compiles a testable core and uses isolated app data; inspect fixture argument/environment requirements before executing private-fixture tests.

For a focused check on macOS use `python3 Tests/run-local-library.py . /private/tmp/stagekeys-focused TestName` from the repo root. Use a unique output directory outside the checkout. For broad final validation omit TestName. `Tests/test-reverb.sh` is the C reverb sanitizer suite; Python corpus tests and gate/runner tests appear in CI. Do not substitute an artifact build for a regression reproducing the failure.

Record baseline revision, exact command, expected failure, actual output, generated fixture provenance and final input hashes where useful. Inject failures at meaningful boundaries (preflight, instantiate, graph reconnect, state restore, restart, save) and assert retained rendering/state/bytes as well as the error. Use deterministic clocks/tokens or bounded event-loop waits rather than arbitrary sleeps. Inspect crash stack and first assertion before broadening changes.

Run directly affected tests after the last edit. Broaden when shared behavior or unresolved risk warrants it, without repeatedly rerunning unchanged suites. Report passed, failed, skipped, blocked and unexecuted separately. Known caveat: inspect `PianoHeldNoteTests` at the current revision; it has reported pass without the optional private fixture. Never count that as exercised private-piano coverage. Use [regression](../../templates/regression-testing.md) and [root cause](../../templates/root-cause.md); compilation and model consensus are not evidence of behavior.
