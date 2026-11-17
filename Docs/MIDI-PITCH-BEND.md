# MIDI pitch bend

## What changed

StageKeys accepted notes, controllers, sustain and program change from the
primary controller but had no pitch-bend path: `Store.handleMIDI` fell through
its `switch status & 0xf0` for `0xE0`, so the wheel on a keyboard or pedal was
read, logged in the MIDI Monitor and then ignored. A hosted sampler or Audio
Unit therefore never heard the wheel.

Now:

- `MIDIPitchBend` decodes the 14-bit wheel. Both data bytes mask bit 7, which
  the MIDI specification reserves. The lower half has 8192 steps and the upper
  half 8191, so each side is scaled by its own span and `0`/`16383` land on
  exactly `-1`/`1`; a wheel at rest (`8192`) is `0`.
- `Store.handleMIDI` accepts `0xE0` from the **primary** controller only. A
  secondary controller owns no notes, so it cannot bend them either. The
  accepted position is published as `store.pitchBend` in `-1...1`.
- `AudioController` forwards the position to every installed hosted voice,
  including parallel imported branches. The rack re-encodes it and sends a real
  `0xE0` message to the Audio Unit or sampler.
- `Panic` (CC120/123, the Panic action, Stop Audio and the audio-failure
  panics) recentres the wheel: the published value returns to `0` and a centred
  `0xE0` is sent, so a discarded bend cannot transpose the next chord.
- Out-of-range and non-finite positions clamp or recentre; they never wrap
  around the wheel.

The instrument keeps **its own bend range**. StageKeys forwards the wheel
position unchanged instead of imposing a range, so a sampler's or plug-in's
configured bend range (typically ±2 semitones) decides the audible interval.
StageKeys does not claim to change it.

## Known limits

- The internal `Synth.c` voice core has no pitch-bend parameter, so an internal
  synth layer would ignore the wheel. Product notes come from hosted samplers
  and Audio Units, which is the path this change covers; a native-synth bend
  needs a DSP change and is not claimed here.
- A bend is not re-sent after a patch change or graph rebuild: the replacement
  instrument starts centred. Most controllers send the wheel only when it
  moves, so a held bend after a patch change returns on the next wheel move.
  Recentring on Panic is deliberate and tested; continuous re-application
  across a graph edit is not.
- No physical wheel, keyboard or plug-in was exercised in this workspace. The
  hosted macOS `library` job proves the decoding, the primary-only dispatch,
  the forwarded bytes and the recentred wheel on the production store; the
  audible interval still needs a keyboard and a listening check.

## Verification

`Tests/MIDIPitchBendTests.swift` runs in the `library` job with no audio device,
plug-in or hardware. It decodes centre, both extremes, reserved bits, a quarter
of the upper half, round trips, clamping and non-finite input, then drives the
production `PerformanceStore` with a generated MIDI source and the generated
library fixture: a primary bend reaches the hosted rack as `0xE0 0 127`, a
secondary bend is rejected without reaching the rack, `panic()` recentres both
the state and the wire, and stopping audio leaves the wheel centred.

`Tests/test-midi-pitch-bend.py` runs in `processing` and fails if the `0xE0`
case, the primary-only guard, the forwarded event, the recentring, the
regression program or the job wiring is removed.
