# Live graph recovery acceptance — work artifact for #123

This is a work artifact for the PR branch `buffy/issue-123-atomic-live-graph-recovery`.
It is not a claim that the issue is closed.

## Chosen issue

- #123: [P0] Recover atomically from intermittent AVFAudio error -1 during live changes

## Source read for this pass

- Issue #123 body and comments
- `Docs/PUBLIC-RELEASE-CHECKLIST.md`
- `Docs/RELEASE-ISSUES.md`
- `Sources/AudioController.swift`
- `Sources/AudioDevices.swift`
- `Sources/AudioDiagnosticRecorder.swift`

## What this PR scopes

This PR does not claim to reproduce the real intermittent AVFAudio `-1` failure.
It scopes the remaining acceptance items and adds one compile-time hook so the
release verification target can compile against the new fault-injection and
graph-completion-failure paths.

### Acceptance items this PR addresses

- [x] Add a compile-time build foothold for the atomic live-graph recovery
      diagnostic test surface (`AtomicLiveGraphRecoveryHookTests.swift`).
- [x] Record the remaining evidence gaps in a single acceptance artifact
      (`Docs/LIVE-GRAPH-RECOVERY-ACCEPTANCE.md`).

### Acceptance items still open

- [ ] Capture the real intermittent AVFAudio `-1` failure on this Mac with the
      triggering control, output route, rate/block size and operation-scoped
      diagnostics. Fault injection is not that reproduction.
- [ ] Verify held notes/sustain, Tonic Pad and metronome state during the real
      failure/recovery.
- [ ] Run repeated sound/effect/patch edits with native samplers and real hosted
      AUs, recording clicks, silence and graph/resource growth.

## Non-goals

- No proprietary samples, presets, plugins, device state or user content are
  included or redistributed by this PR.
- No issue closure is requested by this PR.
