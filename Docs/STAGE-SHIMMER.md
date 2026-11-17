# Stage Shimmer

Stage Shimmer is an opt-in versioned core for Halo Shimmer (effect ID 10).
New factory instances use `stage-shimmer-v1`; patches without an `effectCore`
keep the legacy pitch-shifted feedback reverb. Existing patches are never
silently migrated.

## Signal path

The public controls and their indices are unchanged:

1. Amount
2. Feedback
3. Size
4. Diffusion
5. Modulation
6. Low Cut
7. Tone
8. Dry
9. Wet
10. Quality

Stage Shimmer moves the octave pitch shifter ahead of the diffusion tank. The
shifter receives the direct signal, and Amount crossfades that shifted signal
with the direct signal before the four-line room and two allpass stages. Room
size, feedback, damping and diffusion therefore shape the wet network without
changing the pitch source. Quality changes only the pitch shifter's analysis
size; the legacy whole-effect decimation clock is not used by this core.

Amount, feedback, size, diffusion and modulation are smoothed over 20 ms. Low
Cut, Tone, Dry and Wet retain the existing 20 ms smoothing. The tank uses the
preallocated delay history, the existing per-side line spacing, and no new
render allocation, lock, I/O, logging or framework call. The existing
phase-vocoder shifter remains the pitch implementation; no upstream source is
copied or adapted for this core.

## Compatibility

- Public control indices 0 through 9 are unchanged.
- Hidden render selector index 10 appends `0` for the legacy core and `1` for
  `stage-shimmer-v1`.
- `AudioEffect` stores `effectCore`; presets, snapshots, and AU settings carry
  the selector through `renderValues`.
- Changing the core clears the delay, tank, pitch shifter and stage controls so
  the selected core starts deterministically.
- Existing patches, imported effects without a selector, and saved presets keep
  the legacy processor.

## Automated verification

`Tests/StageShimmerTests.c` covers 44.1, 48, and 96 kHz with exact dry at Wet 0,
octave content with feedback disabled, quality changes, damping, smoothed
automation, bounded feedback, Panic silence, and eight instances.

`Tests/EffectPresetTests.swift` checks the Stage Shimmer identifier, hidden
selector, factory default, preset round trip, and legacy nil-core behavior. The
Swift test and Apple build have not run in this Linux-only environment.

## Pending qualification

- Matched Halo Shimmer reference captures and blind listening on piano, organ,
  pad and synth.
- Measured octave accuracy, grain latency, stereo width, transient smearing,
  alias energy and feedback stability against the legacy core.
- Release-build CPU, memory, latency and dropout measurements for one, three,
  and eight instances, including physical iPad testing.
