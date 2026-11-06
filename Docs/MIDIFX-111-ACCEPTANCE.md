# #111 acceptance matrix — Play In/Hear In and patch tempo lock

Issue #111 asks for patch-level musical transposition, explicit octave direction,
patch tempo lock, sample-accurate tempo propagation, migration of those settings,
and the tests listed in its acceptance criteria. This file records which of those
requirements have evidence, which are covered only by the hosted macOS gate, and
which remain open. **It is an audit, not a closure.** The issue stays open until
the unverified rows are measured or the owner changes its scope.

Status values:

- **Verified** — a named Linux program was compiled with `-DDEBUG` (assertions
  on, no `-O`) and run here; the result is reproducible from the commands below.
- **Gated** — the check exists and runs in the default macOS library gate, but
  could not be compiled or run on this machine (no AVFoundation, Xcode or audio
  hardware). It is not counted as passing here.
- **Reasoned** — the behaviour follows from the pure arithmetic, but no test or
  measurement isolates it. Not evidence.
- **Open** — no implementation or no evidence.

## Acceptance criteria

| # | Requirement | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Patch-level Play In and Hear In keys with deterministic semitone behaviour | Verified | `Tests/PatchTranspositionTests.swift` covers all 12 × 12 key pairs for `nearest`, `up` and `down`, asserts each distance reaches the Hear In key, and pins D→C to −2 / +10 / −2 |
| 2 | Explicit octave-direction controls instead of always the shortest interval | Verified | `KeyDirection` and `Patch.octaveShift`; `PatchTranspositionTests` checks octave wrapping, ±24 semitone clamping and out-of-range clamping |
| 3 | Key changes transpose Easy Chord and Sequencer input/output without cumulative drift, preserving the authored source | Verified | 200 alternating key changes return the same value; authored `MIDIProgram` compares equal after every key; out-of-range output notes are dropped, not wrapped |
| 4 | Tap, stepper and direct-entry tempo controls with a patch lock that separates live tempo from patch-recalled tempo | Verified for the contract, **unverified for the UI** | `PatchTransposition.recallsPatchTempo` / `resolvedTempo` matrices pass; `Tests/ProgramChangeOptInTests.swift` exercises the virtual-MIDI Store tempo contract. The SwiftUI tap/stepper/BPM entry and their invalidation are source-reviewed only, not walked through |
| 5 | Tempo changes reach supported delays, tremolo, arpeggiators and sequencers without phase discontinuity, doubled triggers or stuck notes | **Partial** | Arpeggiator and sequencer: `Tests/TempoContinuityTests.swift` (Verified) plus the arpeggiator case in `PatchTranspositionTests`. Native delay: `Tests/DelayTempoTransitionTests.c` measures a 1.0× steady slope across a crossfade at 44.1/48/96 kHz. Tremolo: `Reasoned` — it is an audio-effect parameter, and no test measures its phase across a tempo change |
| 6 | Persist and migrate across setlist duplication, library export/import and MainStage conversion | **Partial** | Save/reload, whole-setlist round-trip, duplication, v3→current upgrade, legacy documents without the fields, and `SessionSettings.liveTempo` are asserted by `Tests/TranspositionPersistenceTests.swift` (Gated — AVFoundation types, macOS only) and `Tests/ModelTests.swift` (Gated). Setlist-share packages and library backup are covered only structurally: the fields are ordinary `Codable` patch members and travel inside the setlist JSON, which `Tests/SetlistShareTests.swift` round-trips; no test asserts these five fields after a share export. MainStage conversion does not derive patch-level musical transposition — layer transpose is converted separately — so it neither loses nor invents these fields. **Open as explicit coverage.** |
| 7a | Unit tests for all 12 keys, octave wrapping, repeated key changes and chord/sequence mappings | Verified | Criteria 1–3 above |
| 7b | Restart coverage | Gated | `ModelTests` (round-trip), `ProgramChangeOptInTests` and `SetlistActivationTests` restart a `PerformanceStore` and assert locked vs live tempo; none ran here |
| 7c | Live MIDI tests with sustain and patch changes | **Open** | `ProgramChangeOptInTests` sends virtual-MIDI notes and asserts held keys, but no physical keyboard, sustain pedal or patch-change timing was exercised. macOS and hardware only |

## Tempo continuity, as measured

`Tests/TempoContinuityTests.swift` drives `MIDIFXProcessor` with an explicit clock
(`automaticallySchedule: false`), so the numbers are scheduler arithmetic, not
timer or audio-render measurements:

| Case | Assertion |
| --- | --- |
| Arpeggiator 120 → 60 BPM | Steps at 0.00, 0.25 s; after the change at 0.25 s the next step is 0.75 s. No step at 0.50 s, none duplicated |
| Arpeggiator 60 → 120 BPM | Steps at 0.00, 0.50 s; next step 0.75 s — one eighth note after the change, not early |
| Sequencer 120 → 60 BPM | Authored order 60, 64, 67 continues; the step emitted at the change is not repeated |
| Mapped sequencer 120 → 90 BPM | Mapped output 40, 45, 52 continues in order across the change |
| 48 alternating 120/60 changes | Pitch order is exactly the authored 4-step cycle repeated; onset times are strictly increasing with no duplicate |
| Redundant tempo write | Re-applying the current tempo emits nothing and advances no step |
| Note release | Every generated key receives a note-off after the held key is released |

## What these checks do not establish

- **Audible timing.** No audio was rendered or heard. The scheduler hands events
  to the audio timeline, but whether an Audio Unit places them at the intended
  sample is unmeasured; `Tools/AUOnsetHarness.swift` exists and has never run.
- **Physical input.** No keyboard, sustain pedal or patch-change switch was used.
  Virtual-MIDI tests do not cover a real device's scan and timestamp path.
- **Tremolo phase.** No test isolates tremolo across a tempo change.
- **UI.** The key grid, direction picker, octave stepper and tempo controls were
  not driven; they are compiled by the macOS gate at most.
- **Share and backup migration of these fields.** Not asserted after export.
- **Parity with a reference application.** Nothing here compares against Sunday
  Keys; the semantics come from its published manual, and the implementation is
  independent.

## Reproduction

```
swiftc -DDEBUG Tests/PatchTranspositionTests.swift Sources/MIDIFXProcessor.swift Sources/MIDIPrograms.swift -o /tmp/patch && /tmp/patch
swiftc -DDEBUG Tests/TempoContinuityTests.swift Sources/MIDIFXProcessor.swift Sources/MIDIPrograms.swift -o /tmp/tempo && /tmp/tempo
```

The persistence program needs the macOS gate:

```
xcrun swiftc -DDEBUG -import-objc-header Sources/Bridge.h <sources> Tests/TranspositionPersistenceTests.swift ...
```

On Linux it compiles and prints `SKIP`, because `Patch` reaches AVFoundation.

## Remaining work in dependency order

1. Run `Tests/TranspositionPersistenceTests.swift` in the macOS gate and report
   the result. It is written but not yet executed anywhere.
2. Add a share-package assertion for the five fields (`SetlistShare.make` →
   `encode` → `decode`), which the macOS gate can run.
3. Measure tremolo phase across a tempo change, or state plainly that tremolo is
   not tempo-synced.
4. Compile `AudioController`/`ExternalInstruments`/`Store` and run
   `Tools/AUOnsetHarness.swift`; without this, "sample-accurate" remains a design
   intent for the AU path. The seven-PR scheduling stack is reviewed at
   [MIDIFX-SCHEDULING-STACK-REVIEW.md](MIDIFX-SCHEDULING-STACK-REVIEW.md).
5. Qualify sustained notes and patch changes on a physical keyboard.

Until 1–5 are reported, the honest summary is: the musical arithmetic, the
scheduler's tempo continuity for arpeggiator and sequencer, and the delay
crossfade have evidence; audible sample placement, tremolo and hardware remain
open.
