# Stage Pitch Shifter

Stage Pitch Shifter is an opt-in versioned core for effect ID 12. New factory
instances use `stage-pitch-v1`; patches without an `effectCore` keep the legacy
two-head pitch shifter and are never silently migrated. The editor identifies
the active core and offers an explicit upgrade.

## Signal path

The public controls and their indices are unchanged:

1. Pitch in semitones selects the playback ratio.
2. Amount controls the wet blend.

Both cores use a 60 ms, two-head granular window over the existing preallocated
delay history. Stage Pitch reads the two heads with the existing cubic
interpolator and smooths the pitch ratio and amount over 20 ms. Pitch 0 or
Amount 0 selects exact dry output; changing either target fades to dry instead
of stepping. The legacy core remains available for existing patches.

The core adds no allocation, lock, I/O, logging, framework call, or resampling
buffer to the render path. It reuses the engine's fixed delay storage and the
already admitted cubic interpolation primitive. Signalsmith Stretch is not
imported or adapted for this core.

## Compatibility

- Public control indices 0 and 1 are unchanged.
- Hidden render selector index 2 appends `0` for the legacy core and `1` for
  `stage-pitch-v1`.
- `AudioEffect` stores `effectCore`; presets, snapshots, and AU settings carry
  the selector through `renderValues`.
- A selector change clears the pitch delay and head phase so the chosen core
  starts deterministically.
- Existing patches, imported effects without a selector, and saved presets keep
  the legacy processor.

## Automated verification

`Tests/StagePitchTests.c` runs under AddressSanitizer and UndefinedBehaviorSanitizer
at 44.1, 48, and 96 kHz. It checks exact dry at Pitch 0 and Amount 0, upward and
downward pitch content, a smoothed amount step, rapid pitch/amount automation,
finite/bounded output, Panic silence, and eight independent instances.

`Tests/EffectPresetTests.swift` checks the Stage Pitch identifier, hidden
selector, factory default, preset round trip, and legacy nil-core behavior. The
Swift test and Apple build have not run in this Linux-only environment.

## Pending qualification

- Render-safe Signalsmith Stretch comparison, including pitch accuracy and
  reported latency.
- Chord tracking, transient smearing, metallic coloration, and alias
  measurements against an oversampled reference.
- Blind, level-matched listening on piano, organ, pad, and synth sources.
- Release-build CPU, memory, latency, and dropout measurements for one, three,
  and eight instances, including physical iPad testing.

No upstream source was copied or adapted for this core.
