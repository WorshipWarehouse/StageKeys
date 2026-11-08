# Sampler disposal ordering and lifecycle evidence — #192

Observed report: `StageKeysMac-2026-11-07-213026.ips` trapped with
`EXC_BREAKPOINT` / SIGTRAP on the main thread inside
`AudioComponentInstanceDispose` while releasing an `AVAudioUnitSampler`. The
abbreviated stack names `PerformanceStore.choose(_:)` → `applyPatch()` →
`ExternalInstrumentRack.finishGraphChanges()`, so the dispose happened during a
patch change rather than at launch or audio startup.

This record describes the implemented teardown ordering and its evidence. It
does not claim the owner's original report was reproduced: no macOS audio device
or AVFoundation runtime exists in the environment that made this change, so the
crash itself is **unreproduced**. The owner scenario, the instrumentation's live
capture and the repeated rapid patch-switch run remain open in #192.

## Implemented behavior

- **One teardown order.** A replaced, evicted or restored sampler is quiesced
  (`auAudioUnit.reset()`), disconnected and detached before its last reference
  is dropped. `ExternalInstrumentRack.quiesceAndDetach(_:channel:)` is the only
  place that disposes a sampler node.
- **Stopped-window release, after the snapshots are gone.** Samplers that leave
  the active graph are queued in `deferredSamplers` instead of being released by
  the transaction's captured sampler list. The queue drains only where no
  snapshot can still hold the node and rendering is stopped: at the start of the
  next graph transaction (`editGraph`, after `engine.stop()`) and during
  `resetForRecovery()`. It is deliberately *not* drained inside
  `finishGraphChanges()` or `restoreGraph()`: `withGraphChanges` keeps its
  rollback snapshot (`nodes`, `routes`, `voices`, `tails`) alive across the
  restart, so a release there would only move the deallocation past
  `engine.start()`. An entry a live `preparedRollback` still references is
  recorded as `snapshotHeld` and kept queued until that snapshot is gone.
- **Tail truncation reaches the same point.** The retained-tail cap and the
  silent-tail purge queue their sampler nodes while those are still attached, so
  `quiesceAndDetach` performs the documented reset before disconnecting and
  detaching. Truncating an audible tail no longer only drops references.
- **Unsafe disposal is reported, not trapped.** If a disposal is ever requested
  while the engine is running, the sampler is not detached. The transaction
  receives `ExternalInstrumentError.unsafeSamplerTeardown`, which is recorded in
  the existing `AudioGraphFailure.restoration` slot so the engine stays stopped,
  the saved document is untouched and the existing explicit retry/`Retry Audio`
  recovery path (#123) is used. The report distinguishes restoration from
  teardown failures by the error code, and the user-facing message explains that
  audio stopped and can be restarted.
- **Rollback safety.** A queued sampler that a rollback re-adopts (the live graph
  or a retained tail references it again) is left alone and recorded as
  `retained`; it is never detached from a graph that owns it.

## Lifecycle evidence

Every build keeps an in-memory bounded (48 entry) ordered log of
`SamplerLifecycleRecord` values: `event`, optional channel, graph generation,
`engineRunning`, `attached` and `retainedTail`. Events are `attach`, `retire`,
`evict`, `quiesce`, `detach`, `deferRelease`, `release`, `retained`,
`snapshotHeld`, `deferredWhileRunning` and `unsafeDisposal`. The log is included
in the existing local support report as the optional `samplerLifecycle` field,
which is absent until something is recorded. Recording is not compiled out of
release builds: the reported trap happens in release, so a field capture from a
recurrence has to come from a shipped build. The log is bounded and holds no
plug-in state, file path, sample payload, MIDI data or user text.

`release` is written only after the queue has dropped its reference for that
sampler, so it describes a completed disposal rather than a local copy. DEBUG
builds also keep a weak probe per queued sampler:
`debugUndeallocatedSamplerCount` reports how many released samplers still have an
owner, which is how the regression checks actual lifetime completion instead of
trusting the emitted records.

A teardown that throws keeps its sampler queued for the next stopped window
rather than dropping the queue's reference, so an unexpected failure can never
turn a reported error back into the disposal trap.

## Verification

- `Tests/ExternalGraphTailTests.swift` (default library gate) replaces a
  sampler-backed channel repeatedly, exceeding the two-tail cap, and first
  asserts that the replaced samplers are still queued and still alive at the end
  of that transaction — releasing them there is the defect being fixed. It then
  runs the queue in a stopped window with no transaction and asserts that every
  release happened with the engine stopped, the node detached and no retained
  tail still referencing it, that every release recorded a graph generation, that
  no unsafe or deferred-while-running disposal was recorded, that the queue is
  empty, and that the weak probes report no remaining owner, so the queue really
  held the last reference.
- `Tests/SupportDiagnosticsTests.swift` checks the report round-trip, the 48-entry
  bound, that the field stays optional for older reports, and that no private
  text is added.

Both run in the existing offline library gate; they exercise ordering, not a live
Core Audio disposal race. The live-engine path (`deferredWhileRunning` /
`unsafeDisposal`) cannot be exercised without a running output device.

## Remaining qualification

- The owner's original scenario is unreproduced. A captured support report from a
  reproduced or recurring occurrence is still required.
- Repeated rapid patch switching on sampler-backed patches with a live output
  device, including more than two switches, has not been run here. Record the run
  count, patch content and duration.
- Whether a truncated tail may cut audible reverb is unchanged: the cap still
  truncates the oldest retained tail. Only its disposal is now ordered.
- The rollback-snapshot audit is currently proven only by the weak-probe
  assertion. No generated case restarts the engine and then rolls back while a
  sampler is queued, so `snapshotHeld` is covered by inspection rather than by a
  run.
- Third-party Audio Unit teardown, physical iPad behaviour and prolonged live
  soak are separate release gates (#4, #13, #14).
