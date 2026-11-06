# MIDI FX scheduler lookahead

`Docs/MIDIFX-AU-SAMPLE-TIMING.md` left the sample-timed AU path dormant: the
timer fired at each deadline, so generated events reached the host at or after
their musical time and nearly always took the immediate fallback. This change
adds an opt-in horizon so the timer can generate upcoming steps before they are
due, while every event still reports its true musical deadline.

## Behavior

- `MIDIFXProcessor(automaticallySchedule:lookahead:)` accepts a horizon,
  clamped to 0–50 ms. The default is 0, which preserves the previous behavior
  exactly.
- `armTimer()` fires `lookahead` before the earliest pending deadline.
- `dispatch(at:)` advances the musical state to `max(now + lookahead, time)`.
  Steps due inside the horizon are generated now, but `onNoteAt`/`onOffAt`
  report `stepTime` and the gate release's musical time, so a sample-timed
  consumer can place them at the correct `AUEventSampleTime`.
- Because state moves ahead of wall time, a live note-on arriving inside the
  horizon joins at the horizon rather than the wall instant. With the default
  off, and with horizons of a few milliseconds, this is bounded by the horizon.

## Why the default is off

Emitting early is only safe when the consumer can schedule. The same processor
also feeds consumers that cannot:

- external MIDI destinations (`Store.sendMIDI`) send immediately;
- `AVAudioUnitSampler.startNote` has no sample time;
- hosted AUs without `scheduleMIDIEventBlock` fall back to immediate delivery;
- native `sk_render` note commands are applied at a block boundary.

Those would receive notes up to one horizon early. Enabling the horizon in
`Store` waits for the AU path in #161 to be verified and for the immediate
consumers to be deferred or timestamped themselves.

## Verified

Linux, Swift 6.0.3, assertions enabled (`-DDEBUG`, no `-O`):

- `Tests/MIDIFXTimerTests.swift` — with a 10 ms horizon, dispatching at 0.20 s
  releases the 0.20 s gate but emits no step before 0.25 s; dispatching at
  0.24 s emits the 0.25 s step with `onNoteAt == 0.25`; a later dispatch at
  0.25 s does not duplicate it; the step's gate remains at 0.45 s. With a zero
  horizon, dispatching at 0.24 s emits nothing, matching the previous behavior.
- `MIDIFXTests`, `PatchTranspositionTests`, `MIDIAudioTimelineTests` and
  `MIDIDeliveryPolicyTests` still pass.

## Limits

- The horizon is not enabled anywhere in the app, so this change does not alter
  audible timing on its own.
- State moving ahead of wall time means note-on/off during the horizon is
  applied at the horizon. A larger horizon trades more scheduling lead for more
  input delay; 50 ms is the hard cap.
- Timer coalescing and main-run-loop latency are still unmeasured; the horizon
  gives the AU path lead time but does not prove sample accuracy.
- No macOS build, AU run, onset measurement or hardware timing test was run.
  #111 and #10 remain open.
