# Bounded patch preload window — design and measurement plan

Status: **proposed, not implemented.** Nothing in this document ships behaviour, sets a
budget, or asserts a measured improvement. It exists so the code that follows can be audited
against a stated contract instead of being reverse-engineered from a settings toggle.

Issue [#109](https://github.com/WorshipWarehouse/StageKeys/issues/109) asks for bounded
previous/next preload counts with a visible loading state, memory/CPU limits and eviction
rules, and a guarantee that no disk I/O or graph creation happens on the render thread.
That acceptance criterion cannot be met by a validation cache alone, so the open questions
are what a warm entry actually holds, where the bound is enforced, and which numbers the
bound uses.

## Current activation path

Recorded from the code as it stands; these are the call sites the design has to fit.

| Step | Location | What it does today |
| --- | --- | --- |
| Patch selection | `PerformanceStore.select`-family paths in `Sources/Store.swift` | Panics, commits the patch index, then calls `applyPatch()` (`Sources/Store.swift:1030`). |
| Admission | `PerformanceStore.preparePatchActivation` (`Sources/Store.swift:2217`) | Validates the candidate patch's resources before any user state changes. Validation only. |
| Resource preflight | `AudioController.preparePatchResources` (`Sources/AudioController.swift:371`) → `prepareSoundChange` (`:351`) → `ExternalInstrumentRack.validateSound` (`Sources/ExternalInstruments.swift:623`) | Checks component identity, installation and file references. `validateSound` asserts the main thread. No graph edit. |
| Installation | per-layer `AudioController.configure` inside `ExternalInstrumentRack.withGraphChanges` | Loads the sampler or hosts the AU and builds/edits the graph; a failure rolls the graph back to the previous voice. |
| Retained sampler state | `samplerHandles` / `samplerDocuments` (`Sources/ExternalInstruments.swift:828`) | Document state is kept for live samplers and re-applied by `restoreSamplers` after a rebuild. |
| Teardown | `ExternalInstrumentRack.resetForRecovery` | Drops voices, sampler handles and documents. |
| Existing async gate | `AudioController.setPatchLoading` (`Sources/AudioController.swift:475`) | Readiness window for hosted AUs; no preloading of adjacent patches exists. |

There is no preload manager in `Sources` today. The cost worth removing is sampler/AU
instantiation plus graph construction, not `validateSound` — preflight is already cheap and
synchronous, so a "preload" that only repeats it would be invisible to the player.

## Proposed contract

### Settings

Appended optional fields in `SessionSettings`, so older `settings.json` files decode with the
feature off:

- `preloadPrevious: Int?` — 0...4, default 0.
- `preloadNext: Int?` — 0...4, default 0.

Zero in both directions means the current behaviour: no warm entries, no new work on
selection. `validate()` rejects values outside 0...4 so an edited settings file cannot widen
the window.

### Window

Nearest-first, `d` ascending, previous before next at equal distance:

```
window(i) = { i-d | 1 ≤ d ≤ preloadPrevious } ∪ { i+d | 1 ≤ d ≤ preloadNext }
```

Indices are clamped to the setlist; the window does not wrap. Capacity is therefore bounded
by `preloadPrevious + preloadNext` (≤ 8) before any budget is considered, and the active
index is never a warm entry.

### Visible state

`preloadWarming` plus `preloadCompleted`/`preloadTotal` for the current window, rendered next
to the patch name. A cancelled or superseded window reports nothing rather than a stale
count. The existing `patchLoading` gate keeps its current meaning (AU readiness for the active
patch) and is not overloaded to mean "warm entries in flight".

### What a warm entry holds

This is the decision that determines whether the feature is worth its memory, so it is called
out rather than assumed:

- **(a) Validation only** — rejected. No measurable benefit; it would be a toggle that
  claims work it does not do.
- **(b) Retained sampler documents only** — bounded by serialized state, re-installed through
  the existing `restoreSamplers` path on activation. Cheap; removes the reload of authored
  EXS state but not first-note latency for large sample sets.
- **(c) Detached, fully built voice graphs** — the sampler, filter, EQ, compressor and effects
  built off the live graph and attached on activation. Largest gain, largest footprint; needs
  the node-count regression to prove cancelled candidates are torn down.
- **(d) Hosted AU instances ahead of need** — only if the containment gate in #13 passes. A
  blocked main queue cannot be contained by a timeout, so hosting third-party components
  without demand can hang the UI.

Recommendation for the first implementation: (c) for native samplers, falling back to (b)
when a sound's serialized state is small relative to its sample payload, and no AU hosting
(d) until #13's containment evidence exists. Per-entry strategy must be recorded with the
measurement, not inferred from the sound kind.

### Cancellation and failure

- A monotonically increasing window generation is checked between layers; a superseded window
  stops at the next layer boundary.
- Candidates are built off the live graph. On cancel or failure they are released through the
  existing rollback path, never by mutating the live voice.
- A warm entry that fails to load is dropped and reported; the active patch, its saved bytes
  and its audible audio are unchanged. A warm failure may never fail the active patch.
- All work stays on the main queue, matching `validateSound`'s precondition. Nothing is added
  to the render callback, and the audio thread never performs I/O or allocates.

### Eviction

- Entries outside the recomputed window are released immediately on selection.
- If the memory ceiling is reached before the window is full, entries are dropped
  farthest-first, then next-before-previous at equal distance.
- The UI shows the reduced window; it must not present a full window that is not resident.
- Released candidates decrement the same node/voice counters the rollback regression asserts,
  so a leak is a test failure rather than a slow drift.

## Budgets to measure before choosing numbers

No memory or CPU number is asserted here. The following procedure produces the numbers the
implementation will be held to:

1. **Fixtures** — a generated small SF2 (≤ 1 MB), a large streamed sampler from the synthetic
   streaming fixtures, and one hosted AU already used by the gated tests. No private library
   content and no vendor samples.
2. **Instrumentation** — `os_signpost` intervals around window construction; `phys_footprint`
   from `task_info(TASK_VM_INFO)` before and after a window is built; activation latency
   measured from patch selection to first rendered block, with and without a warm entry,
   20 runs each, median and p95.
3. **Pass criteria (to be agreed with the owner)** — zero added render-callback work; steady
   state footprint increase ≤ X MB per warm entry; p95 activation improvement ≥ Y ms; a
   cancelled window leaves the node and tail counts unchanged; the active patch survives a
   warm failure with identical saved bytes.
4. **Recording** — platform, OS build, sample rate, buffer size, patch identity, fixture
   provenance and the exact command, per `AGENTS.md`.

Until those numbers exist, the settings stay at 0 (off) and the feature makes no performance
claim.

## Decisions needed

- **D-P1** — hold strategy (b), (c) or (d) for native samplers, and whether the fallback is
  per sound or per patch.
- **D-P2** — whether hosted AUs may ever be warmed ahead of demand, or only after #13.
- **D-P3** — clamp at setlist edges (proposed) versus wrapping past the ends.
- **D-P4** — the memory ceiling and per-entry budget from the measurements above.
- **D-P5** — whether the UI exposes the two counts separately or as a single "preload depth".

## Not covered here

- Rapid Prev/Next, sustain/tails, missing or offline samples, external storage, restart and
  prolonged performance are hardware qualification on the owner's rig. Generated tests can
  bound the logic; they cannot stand in for that.
- No reference-application behaviour is claimed. Sunday Keys exposes separate preload counts;
  this document defines an independent StageKeys contract, not a parity claim.
- Resource budgets for large content and third-party AUs remain in #4 and #13.
