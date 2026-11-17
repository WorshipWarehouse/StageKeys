# Review guide: MIDI FX scheduling stack

This guide covers the seven draft pull requests that implement the MIDI FX half
of #111's sample-accurate propagation criterion. They are stacked, so each branch
contains the previous one; review in the order below. Nothing here closes #111,
and nothing here claims audible sample accuracy.

Pull request numbers skip because issues and pull requests share GitHub's
numbering. The seven are #159, #160, #161, #162, #164, #167 and #168.

## Claim boundary

The stack has three layers with very different evidence:

| Layer | Status |
| --- | --- |
| Dispatch grid (when the scheduler runs) | Measured in a deterministic simulation |
| Event time and deadline-to-sample arithmetic | Tested as pure functions |
| Audible AU delivery (AVFoundation call sites) | Written, never compiled or run |

Two facts bound the whole stack today:

- The lookahead horizon defaults to 0, so audible timing on `main` is unchanged.
- Audible placement depends on the AU honouring `AUEventSampleTime`. No check
  here proves that any particular AU does.

## Stack

| PR | Branch | Head | Adds |
| --- | --- | --- | --- |
| #159 | `midifx-deadline-scheduling` | `633ebda` | One-shot timer armed at the next musical deadline instead of a 5 ms polling grid |
| #160 | `midifx-audio-timeline` | `980d760` | Per-event musical timestamps and a deadline-to-engine-sample clock |
| #161 | `midifx-au-sample-times` | `49def22` | Sample-timed hosted-AU delivery with a tested pure delivery policy |
| #162 | `midifx-lookahead` | `25a9477` | Opt-in 0–50 ms horizon, default off |
| #164 | `midifx-channel-lookahead` | `e9f8060` | Horizon gated to channels whose AU accepts a future sample time |
| #167 | `midifx-lookahead-refresh` | `5f60ddb` | Recompute the marked set when activation installs finish and when it drains |
| #168 | `midifx-lookahead-clear` | `89fcb6a` | Clear one channel's mark on a rejected install or a retirement |

Each PR carries its own design record: `MIDIFX-SCHEDULING.md`,
`MIDIFX-AUDIO-TIMELINE.md`, `MIDIFX-AU-SAMPLE-TIMING.md`, `MIDIFX-LOOKAHEAD.md`
and `MIDIFX-CHANNEL-LOOKAHEAD.md` (the last covers #164, #167 and #168).

## Per-PR claims and evidence

### #159 — Arm timers at the next deadline

The repeating 5 ms timer quantized every step, gate release and retrigger.
Arming a one-shot timer at `nextDeadline` removes that grid.

Evidence: a deterministic simulation of 260 eighth notes at 132 BPM measured a
worst case of 5.000 ms and a mean of 2.432 ms of lateness on the 5 ms grid,
versus 1 ns when armed at each deadline. The 1 ns is the simulated delivery
offset, not a hardware measurement.

Leaves unverified: OS timer coalescing, main-run-loop latency, any macOS build.

### #160 — Event time and audio-timeline clock

Events now carry the musical time they belong to, gate releases are timed from
the scheduled step rather than a late dispatch, and
`(deadline - anchor) * sampleRate` converts a deadline to engine samples.

Evidence: a step dispatched 10 ms late still reports 0.25 s and gates at 0.45 s;
0.25 s maps to exactly 11025/12000/24000 frames at 44.1/48/96 kHz; non-finite and
extreme input clamps instead of trapping.

Leaves unverified: real render anchors, drift between the host clock and the
audio render clock.

### #161 — Sample-timed AU delivery

Generated AU events are scheduled at an `AUEventSampleTime` derived from the
deadline, with immediate fallback wherever that cannot be proven safe.

Evidence: `MIDIDeliveryPolicyTests` — 20 ms ahead at 48 kHz schedules at +960
frames, 100 frames ahead is immediate, 200 frames schedules, 0.2 s falls outside
the 50 ms horizon, and every missing input falls back.

Leaves unverified: **all AVFoundation wiring.** `AudioController`,
`ExternalInstruments` and `Store` were never compiled. `Tools/AUOnsetHarness.swift`
has never been run.

### #162 — Opt-in lookahead

The scheduler can generate upcoming steps before their deadline while still
reporting the true musical time.

Evidence: dispatching at 0.24 s with a 10 ms horizon emits the 0.25 s step
timestamped 0.25 s; with a zero horizon it emits nothing at 0.24 s.

Leaves unverified: anything audible, because the default is off and nothing in
the app sets it.

### #164 — Per-channel gating

Only channels whose hosted AU has a schedule block advance early. External MIDI,
sampler `startNote` and blockless AUs keep deadline dispatch and are never sent a
note early.

Evidence: with channel 0 marked, dispatching at 0.24 s emits channel 0's 0.25 s
step and nothing for channel 1; dispatching at 0.25 s emits channel 1's step.

Leaves unverified: `canSchedule` / `canScheduleMIDI` themselves, which read the
live rack.

### #167 — Refresh after activation settles

The set is computed from the rack as it is after a change, not as it was before
it. This closes the case where the last channel of a patch switch kept a mark
from its outgoing instrument, and the case where an asynchronously loaded AU was
never marked at all.

Evidence: the processor re-reads the set at dispatch. Marking a channel after
construction takes effect on the next dispatch, and unmarking returns it to wall
time.

Leaves unverified: the Store ordering change, which needs the live
`AVAudioEngine` to exercise.

### #168 — Clear on rejection or retirement

A channel that loses its AU loses its mark, without disturbing the other
channels' marks.

Evidence: clearing channel 1 of two marked channels leaves channel 0 advancing
through the horizon while channel 1 waits for wall time and then reports its own
step time.

Leaves unverified: the callback wiring and the pending-install guard. No test
instantiates a failing AU.

## What is measured, tested, or only reasoned

| Statement | Basis |
| --- | --- |
| 5 ms grid worst case 5.000 ms versus 1 ns deadline ticks | Measured, simulated clock |
| 0.25 s equals 11025/12000/24000 frames | Tested arithmetic |
| Delivery-policy fallbacks | Tested pure function |
| A 10 ms horizon emits the 0.25 s step at 0.24 s | Tested, simulated clock |
| Per-channel gating and per-channel clearing | Tested, simulated clock |
| An AU actually places an event at a future sample time | Reasoned only |
| Store refresh ordering after a real install | Reasoned only |
| Onset jitter on hardware | Not measured |

## macOS review plan

1. Build the project (`Tools/verify-release.sh mac <build-dir>`) and fix any
   compile errors in `AudioController`, `ExternalInstruments` and `Store`. They
   have never been type-checked.
2. Run `Tools/AUOnsetHarness.swift`. It should show a 1024 ± 2 frame onset
   difference. A failure means the AU ignores scheduled MIDI and the timestamps
   are cosmetic.
3. Add a test that switches a patch from a schedule-capable AU on layer 14 to
   external MIDI with a nonzero horizon, and assert the external note is not sent
   early (the #167 claim).
4. Add a test with an AU that fails to instantiate, and assert the channel's mark
   is cleared (the #168 claim).
5. Only then consider setting a horizon in the app. Until step 2 passes, keep the
   default at 0.

## Not in scope

- The native `sk_render` path and #10 remain open. This stack covers the hosted-AU
  MIDI FX path only.
- No hardware timing, USB or Bluetooth MIDI latency, or iOS behaviour.
- No claim of parity with any reference app.

## How the Linux checks were run

Swift 6.0.3 (Ubuntu 24.04), assertions enabled (`-DDEBUG`, no `-O`, which would
compile `assert` out):

```
swiftc -DDEBUG Tests/MIDIFXTimerTests.swift Sources/MIDIFXProcessor.swift Sources/MIDIPrograms.swift Sources/MIDIAudioTimeline.swift Sources/MIDIDeliveryPolicy.swift -o /tmp/t && /tmp/t
```

The same pattern covers `MIDIFXTests`, `PatchTranspositionTests`,
`MIDIAudioTimelineTests` and `MIDIDeliveryPolicyTests`. Repository gates:
`Tests/test-library-gate.py`, `Tests/test-local-library-runner.py`,
`Tests/test-distribution.py` and `Tools/check-distribution.py`.
