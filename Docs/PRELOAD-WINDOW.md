# Bounded patch preload window — design and measurement plan

Status: **decisions settled, not implemented.** The hold strategy, window shape and hard
capacity bound below are decided; the byte ceiling is not, because it needs the measurements
this document describes. Nothing here ships behaviour or asserts a measured improvement. It
exists so a future implementation can be audited against a stated contract instead of being
reverse-engineered from a settings toggle.

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
| Patch selection | `PerformanceStore.choose` → `choosePrepared` (`Sources/Store.swift:1012`) | Admission, then panic and commit the patch index, then `applyPatch()` (`Sources/Store.swift:1030`). |
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
only when the detached candidate cannot be built safely, and no AU hosting
(d) until #13's containment evidence exists. Per-entry strategy must be recorded with the
measurement, not inferred from the sound kind. The fallback is a deliberate capability
decision made before preparation; it must not mask a load, graph-transaction, restoration or
restart failure as a successful warm.

### Cancellation and failure

- A monotonically increasing window generation is checked between layers; a superseded window
  stops at the next layer boundary.
- A candidate is detached from the audible graph and has no path to the output. Staging must
  not enter the live graph-edit/rollback path if that path stops the running engine. On cancel
  or failure, release the candidate's own resources and discard any late result whose
  generation has expired. Cleanup must not invoke live rollback, stop the engine or touch the
  active voice. If the framework cannot safely stage a candidate without those live effects,
  defer warming until a safe preparation path exists.
- A warm entry that fails to load is dropped and reported; the active patch, its saved bytes
  and its audible audio are unchanged. A warm failure may never fail the active patch.
- Run blocking resource preparation in a bounded worker with one in-flight job.
  Recheck cancellation before handing prepared data back to the main queue.
  Keep graph installation on its required queue. Defer warming any sampler that
  can still block that queue on file I/O until a safe preparation path exists.
  The render callback does no preload work.

### Eviction

- Key each entry by patch UUID and the warm-relevant sound and processing
  configuration. Discard entries when the patch leaves the window or those inputs
  change. An index can locate a patch but cannot establish cache identity after
  insertion, removal, reorder or setlist replacement.
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
   measured from patch selection to the first rendered block containing a
   distinct test note from the selected patch, with and without a warm entry.
   Issue the note once the selected patch is ready and unmuted. Previous-patch
   audio and muted loading blocks do not satisfy the marker. Measure
   20 activation runs per condition and report median and p95. For CPU, capture
   process CPU use and render deadline misses over matched fixed-duration intervals with
   preloading off, while the window is actively warming, and after the window is resident.
   Keep the active performance and audio configuration the same across conditions and report
   the measurements; do not infer a CPU budget from a visual spot check.
3. **Pass criteria (to be agreed with the owner)** — zero added render-callback work; steady
   state footprint increase ≤ X MB per warm entry; p95 activation improvement ≥ Y ms;
   peak warming and steady state CPU within agreed limits relative to the
   no-preload control, with zero additional render deadline misses; a
   cancelled window leaves the node and tail counts unchanged; the active patch survives a
   warm failure with identical saved bytes.
4. **Recording** — platform, OS build, sample rate, buffer size, patch identity, fixture
   provenance and the exact command, per `AGENTS.md`.

Until those numbers exist, the future settings default to 0/0 (off) and the feature makes no
performance claim.

## Decisions

Settled for the first implementation slice.

- **D-P1 — hold strategy: (c), detached native voice graphs.** A native sampler sound is
  instantiated and wired into a complete voice without editing or stopping the live graph.
  On activation,
  validate patch identity and adopt the prepared sampler and processing nodes
  as one candidate. If reconnection reinitializes the sampler and requires a
  document reload, treat the attempt as a cold activation and record it as such.
  Claim warm adoption only when the retained sampler renders without a reload.
  Hosted AUs are never warmed (see D-P2).
  Strategy (b) survives only as a fallback for a candidate that cannot be built safely; the
  fallback is decided per sound and recorded on the entry, because one sound's serialized
  state is what decides whether the cheaper form is enough. Validation-only (a) stays
  rejected: it would be a control claiming work it does not do.
- **D-P2 — no AU warming before #13.** A blocked main queue cannot be contained by a timeout,
  so hosting a third-party component ahead of demand can hang the UI. Revisit only with that
  issue's containment evidence.
- **D-P3 — clamp, do not wrap.** At the first patch the window preloads forward only. Wrapping
  would warm a patch the player may never reach and would make the window depend on setlist
  length rather than distance.
- **D-P4 — count-bounded before byte-bounded.** The intended hard capacity is at most 4 per
  direction and 8 warm entries in total; the implementation must enforce that limit regardless
  of settings-file contents. The byte ceiling is one constant, `preloadMemoryCeilingBytes`,
  left unset until the harness below produces numbers; once set, entries are evicted
  farthest-first, then next-before-previous, until it holds. No MB figure is claimed before
  that measurement. When introduced, the feature defaults to off (0/0).
- **D-P5 — two separate counts.** Previous and next remain separate 0...4 values rather than a
  combined depth control, because the need differs by direction within a set.

Still open: the byte-ceiling value (blocked on measurement), whether the (b) fallback is
permitted in a release build or debug-only, and the hardware matrix.

## Not covered here

- Rapid Prev/Next, sustain/tails, missing or offline samples, external storage, restart and
  prolonged performance are hardware qualification on the owner's rig. Generated tests can
  bound the logic; they cannot stand in for that.
- No reference-application behaviour is claimed. Sunday Keys exposes separate preload counts;
  this document defines an independent StageKeys contract, not a parity claim.
- Resource budgets for large content and third-party AUs remain in #4 and #13.
