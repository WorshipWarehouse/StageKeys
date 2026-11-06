# MIDI FX audio-timeline timebase

`Docs/MIDIFX-SCHEDULING.md` removed the 5 ms polling grid and left one gap: even
a deadline-perfect dispatch still handed generated notes to the host at
"now". This record adds the audio-timeline timebase — each event's musical time
is retained, and a pure clock converts it to engine sample time — and states
plainly that the audible AU delivery is still not wired.

## Where generated notes actually go

The arpeggiator/sequencer output does not reach `sk_render`. The product path is:

1. `Sources/Store.swift` — `midiFX.onNoteWithSource` calls `audio.noteOn`.
2. `Sources/AudioController.swift` — `noteOn` forwards only to the hosted rack;
   the native synth has no product note-on caller ("product notes require user
   content").
3. `Sources/ExternalInstruments.swift` — `ExternalInstrumentRack.midi` sends
   `AVAudioUnitMIDIInstrument.sendMIDIEvent` when available, otherwise
   `auAudioUnit.scheduleMIDIEventBlock(AUEventSampleTimeImmediate, …)`.
4. Imported sampler branches call `AVAudioUnitSampler.startNote`, which takes no
   sample time.

So audible sample accuracy depends on `AUEventSampleTime` and a host/render
clock, not on a C render-loop change. That is why this change is in the
scheduler and its clock rather than in `Synth.c`.

## What this change adds

- `MIDIFXProcessor.onNoteAt` and `onOffAt` report the musical time of every
  event alongside the existing callbacks. A step dispatched late still reports
  its scheduled time; a skipped tick reports the step that was due.
- Gate releases and overlapping-note releases are timed from the scheduled step
  (`stepTime + period * gate`) instead of the late dispatch time. When dispatch
  is on time the values are identical; when late, the gate no longer stretches
  by the dispatch delay.
- `Sources/MIDIAudioTimeline.swift` converts a musical deadline to engine sample
  time from a render anchor `(sampleTime, hostTime)`:
  `sample = anchorSample + round((deadline - anchorTime) * sampleRate)`. It
  reports negative offsets for deadlines before the anchor, clamps extreme input
  instead of trapping, and exposes `isDeliverable` so a caller can choose
  immediate delivery for an event that is already behind the render.

## Verified

Linux, Swift 6.0.3 (Ubuntu 24.04), assertions enabled (`-DDEBUG`, no `-O`):

- `Tests/MIDIFXTimerTests.swift` — deadline selection, plus scheduled times: a
  step dispatched 10 ms late still reports 0.25 s; its gate closes at 0.45 s;
  a tick that skips a period reports the due step at 0.5 s with a 0.7 s gate.
- `Tests/MIDIAudioTimelineTests.swift` — 0.25 s maps to exactly 11025/12000/24000
  frames at 44.1/48/96 kHz; 1 ms at 48 kHz is 48 frames; half a frame rounds to
  the anchor; past deadlines are negative; infinity, NaN, a zero rate and ±1e18 s
  do not trap or fabricate a deadline; deliverability is strict.
- `Tests/MIDIFXTests.swift` and `Tests/PatchTranspositionTests.swift` still pass,
  so routing, gate, sequence, panic, tempo lock and tempo phase are unchanged.

## Remaining wiring (not done here)

The clock and timestamps have no consumer yet. Making audible output
sample-accurate requires, on macOS:

1. Capturing `engine.outputNode.lastRenderTime` on the main thread and anchoring
   `MIDIAudioTimeline` with its `sampleTime` and `hostTime`.
2. Computing `AUEventSampleTime` for each `onNoteAt`/`onOffAt` deadline and
   threading it from `Store` through `AudioController` to
   `ExternalInstrumentRack.midi`, replacing `AUEventSampleTimeImmediate`.
3. Falling back to immediate delivery when the block is nil, the event is behind
   `isDeliverable`, or the AU ignores future sample times.
4. Deciding what to do for `AVAudioUnitSampler.startNote` and
   `AVAudioUnitMIDIInstrument.sendMIDIEvent`, which expose no sample time; their
   `auAudioUnit.scheduleMIDIEventBlock` may be used where the AU honors it.
5. Measuring onset on macOS with an AU that honors scheduled MIDI, since an AU
   that silently applies events immediately would make the timestamps
   cosmetic.

This workspace has no AVFoundation, no macOS SDK and no audio hardware, so that
wiring could not be compiled, run or measured here. It is deliberately not
included: the repository's evidence rules forbid claiming sample accuracy from
an unbuilt call site. #111 and #10 remain open.

## Limits

- Audible timing is unchanged by this change; only the scheduler's event times
  and the conversion arithmetic are new.
- The anchor is arithmetic only. Clock drift between the host clock and the
  audio render clock, timer coalescing and the lookahead horizon are not
  measured.
- `MIDIAudioTimeline` assumes the engine render rate equals `sampleRate` and
  that a sample time is valid in the same timeline as the scheduled AU event;
  resampling nodes or per-AU timelines may violate that and need verification.
