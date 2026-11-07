# Preload surface and #109 acceptance status

This note records what the preload work now exposes, and which acceptance
material in #109 is implemented, evidenced or still unverified. It uses no
closing keyword and does not claim that #109 is resolved.

## What the surface shows

Settings → Performance carries two counts, **Preload Previous Patches** and
**Preload Next Patches**, each bounded to 0...4 (`SessionSettings.preloadLimitPerDirection`).
The window is nearest-first, clamped at the setlist edges, never contains the
active patch and holds at most 8 entries because each direction is bounded.

Below the counts, one status line reads:

- `Preloading off` — both counts are 0 (the default, and what a legacy settings
  file loads as).
- `Ready n of m` — `n` entries of the current window hold a detached voice.
- `Preparing n of m…` — a warm pass is currently running.

This state is separate from `patchLoading` so "the active patch is loading" and
"a neighbour is being prepared" cannot be confused in the UI. Neither value is
read on the render path.

## Cancellation and failure

Each scheduled pass carries a generation. A selection, a count change or a
setlist change increments it, cancels the pending work item, and any pass still
running stops before its next patch. A warm failure never touches the active
voice: `warm` builds a chain that has no edge to `mainMixerNode`, so a failed or
abandoned entry cannot be heard, and an entry that fails to build is simply not
recorded in `warmedChannels`.

## Acceptance mapping

| #109 criterion | State | Evidence |
| --- | --- | --- |
| Bounded previous/next counts and a visible loading state | Implemented | `Tests/PatchPreloadTests.swift` (bounds, clamping, eviction, persistence, visible state, rapid selection) |
| No disk I/O or graph creation on the render thread | Implemented by construction | Warming runs from `DispatchQueue.main.asyncAfter`; `AudioController` forwarding calls the rack outside any render block |
| Memory/CPU limits and eviction rules | Count-bounded only | Eviction by recomputation; ≤4 per direction, ≤8 total. The byte ceiling is deliberately unset (D-P4) — no measured figure exists |
| Active patch survives failed/cancelled preloads | Implemented | Detached chain has no output edge; adoption only on a matching signature; `Tests/PreloadWarmVoiceTests.swift` covers AU refusal and discard |
| Separate keyboard playability and played-note display | Landed earlier (#136) | `Docs/KEYBOARD-PERFORMANCE-CONTROLS.md` |
| Dynamic MIDI-FX range mode | Landed earlier (#139) | `Docs/DYNAMIC-MIDI-RANGES.md` |
| Optional per-sound meters | Proposed in PR #154 | `Docs/SOUND-METERS.md` on that branch |
| Rapid Prev/Next, patch lock, sustain/tails, missing samples, AU failures, external storage, restart, prolonged performance | Partly | Rapid selection and stopped-engine state are covered by `PatchPreloadTests`; sustain/AU/missing-sample paths are covered offscreen in `PreloadWarmVoiceTests`. Real-rig qualification, external storage and prolonged performance are **not** verified here |

## What remains unverified

- No measurement of warm latency, resident memory or CPU on any machine. The
  counts are a capacity bound, not a measured budget.
- No real-rig run: physical keyboard, sustain pedal, USB MIDI, VoiceOver/focus
  order, external drives, restart under load and a long performance set.
- The byte ceiling, the per-sound fallback for AU-backed patches and the
  hardware matrix remain open decisions.

Passing the Linux library gates and any hosted macOS build establishes the
exercised software behaviour only.
