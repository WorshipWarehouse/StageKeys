# Draft: sample-timed AU delivery

`Docs/MIDIFX-AUDIO-TIMELINE.md` gave the scheduler a musical time and a
deadline-to-sample clock. This draft wires that clock to the hosted-AU note path.
It is **not verified**: the AVFoundation call sites were written in a Linux
workspace without a macOS SDK and were not compiled, run or measured. The pure
decision logic is tested; the wiring and onset harness are for macOS review.

## Wiring

- `Store` now installs `midiFX.onNoteAt` / `onOffAt` and passes each event's
  musical deadline to `AudioController.noteOn` / `noteOff` (`at:` parameter).
  Direct keyboard notes pass no deadline and behave exactly as before.
- `AudioController.auDelivery(for:canSchedule:)` anchors from
  `engine.outputNode.lastRenderTime`: it converts the host-time distance since
  that render into frames, builds `MIDIAudioTimeline(currentSample, now)`, and
  asks `MIDIDeliveryPolicy` whether the deadline can be scheduled.
- `ExternalInstrumentRack.midi` takes an optional sample time and, when present
  and the unit has `scheduleMIDIEventBlock`, sends the bytes with
  `AUEventSampleTime(sample)`. `noteOn`/`noteOff` thread the value through so a
  re-triggered pitch stops and starts at the same timestamp.

## Fallbacks

`MIDIDeliveryPolicy` returns `.immediate` for every case it cannot prove safe:

| Case | Result |
| --- | --- |
| No deadline (direct keyboard note) | immediate |
| No valid `lastRenderTime` or host time | immediate |
| Deadline beyond the 50 ms lookahead | immediate |
| Event leads the render by ≤ 128 frames | immediate |
| Destination cannot schedule (no block) | immediate / `sendMIDIEvent` |
| Already behind the render position | immediate |

`sendMIDIEvent` has no timestamp, so `AVAudioUnitMIDIInstrument` units that lack
a schedule block keep immediate delivery even when a sample time was computed.

## Tested here

Linux, Swift 6.0.3, assertions enabled:

- `Tests/MIDIDeliveryPolicyTests.swift` — 20 ms ahead at 48 kHz schedules at
  +960 frames; 100 frames ahead is immediate; 200 frames ahead schedules; a
  0.2 s deadline is outside the lookahead; past deadlines, missing deadline,
  timeline, current sample or scheduling support all fall back; non-finite
  deadlines fall back.
- The existing `MIDIFXTimerTests`, `MIDIAudioTimelineTests`, `MIDIFXTests` and
  `PatchTranspositionTests` still pass.

## Onset harness (not run)

`Tools/AUOnsetHarness.swift` renders a generated 880 Hz tone through
`AVAudioUnitSampler` twice in offline manual-rendering mode, scheduling the note
at sample 0 and at sample 1024 via `scheduleMIDIEventBlock`. It compares the
first frame above a threshold and asserts the onsets differ by 1024 ± 2 frames.
Run on macOS:

```
xcrun swiftc -DDEBUG Tools/AUOnsetHarness.swift -o /tmp/au-onset && /tmp/au-onset
```

It is deliberately outside `Tests/` because it needs macOS, AVFoundation and an
instrument AU, and it has not been run.

## Limits and risks

- **Lookahead now exists but is off by default** ([MIDIFX-LOOKAHEAD.md](MIDIFX-LOOKAHEAD.md)). Without it, events arrive at or after their deadline and take the immediate fallback. Enabling it would also feed immediate consumers (external MIDI, `startNote`, AUs without a schedule block) up to one horizon early, so it waits until this path is verified. Do not read this draft as sample-accurate.
- `AUEventSampleTime` is interpreted in the AU's render timeline; the wiring
  assumes that timeline matches `engine.outputNode.lastRenderTime`. Resampling
  nodes, per-AU timelines, or an engine that has not started may violate that.
- Parallel imported branches run their own MIDI FX clocks and still deliver
  immediately; so do `AVAudioUnitSampler.startNote`-based branches and
  `sendMIDIEvent` units without a schedule block.
- `control` events (sustain, force-release) remain immediate.
- No macOS build, no AU compatibility check, no rendered onset measurement, and
  no hardware timing test was run. #111 and #10 remain open.
