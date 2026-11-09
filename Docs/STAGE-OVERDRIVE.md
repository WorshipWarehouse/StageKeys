# Stage Overdrive

Stage Overdrive is an opt-in versioned core for effect ID 11. New instances use
`stage-overdrive-v1`; patches without an `effectCore` keep the legacy filtered
tanh processor and are never silently migrated.

## Signal path

1. One-pole low cut, 20–800 Hz.
2. Drive into an antiderivative-antialiased (ADAA) tanh stage. The transfer
   curve is normalized by `tanh(drive)` so the drive control retains the legacy
   gain convention.
3. One-pole tone low-pass, 600 Hz to 20 kHz.
4. Dry/wet mix and output Boost (-24 to +12 dB).

Drive, low cut, tone, mix, and boost are smoothed over 20 ms. The direct path is
mixed before output gain, so Mix 0 at 0 dB Boost is sample-exact dry. The output
is finite and bounded for every valid combination, including maximum drive and
boost.

The ADAA stage uses the divided difference of `log(2 cosh x)` over adjacent
input samples. It is independent StageKeys DSP, not an Airwindows port. It does
not allocate on the render thread, take a lock, perform I/O, or add a resampling
buffer. The only added persistent state is the previous driven sample and the
existing `EffectState.z` slots; no delay memory is added.

## Compatibility

- Public control indices 0–4 are unchanged.
- Hidden render selector index 5 appends `0` for the legacy core and `1` for
  `stage-overdrive-v1`.
- `AudioEffect` stores `effectCore`; presets, snapshots, and AU settings carry
  the selector through `renderValues`.
- The editor labels the active core and offers an explicit upgrade from the
  legacy core.
- A selector change clears the filter, ADAA, and smoothing state so the new core
  starts from a deterministic state.

## Oversampling decision

No oversampling is added. The core is intended to reduce aliasing at the
existing sample rate through ADAA; adding a multi-rate path would add latency
and CPU cost before a listening and alias comparison justifies it. A rigorous
level-matched alias measurement and blind Airwindows comparison remain pending
(see below), so this core is not claimed to be sonically superior.

## Automated verification

`Tests/StageOverdriveTests.c` runs under AddressSanitizer and
UndefinedBehaviorSanitizer at 44.1, 48, and 96 kHz. It covers:

- exact dry output at Mix 0 and 0 dB Boost;
- a meaningful difference from the legacy core;
- a smoothed (non-switching) mix step;
- rapid automation across all five visible controls;
- finite, bounded output at every sample;
- Panic silence and repeatable reset;
- eight independent live instances for sustained blocks;
- a fixed 8.64 kHz alias probe at 48 kHz. The stage core measured an
  alias/fundamental ratio of 0.01684 versus 0.07100 for the legacy core, about
  4.2× lower alias energy. This is a diagnostic, not a listening claim or an
  oversampled-reference comparison.

`Tests/EffectPresetTests.swift` checks the core identifier, render selector,
factory default, preset round trip, and legacy nil-core behavior. The Swift
check cannot run in this Linux-only environment; it is covered by the Apple
build/test job.

## Pending qualification

- Blind, level-matched listening on piano, organ, synth, and stereo pad.
- A documented Airwindows PurestDrive/Drive review at pinned revisions. No
  Airwindows source was copied or adapted for this core; the existing
  `Licenses/Airwindows-MIT.txt` remains present for the independent CreamCoat
  work.
- Comparison of the alias probe against a host-rate oversampled reference;
  the legacy-core comparison above is not a substitute for that check.
- Release-build CPU, memory, latency, and dropout measurements for one, three,
  and eight instances, including physical iPad testing.

These checks must pass before the core is promoted beyond an opt-in candidate or
is described as a musical improvement.
