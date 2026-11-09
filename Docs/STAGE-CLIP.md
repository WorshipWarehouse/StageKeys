# Stage Clip Distortion

Stage Clip Distortion is an opt-in versioned core for effect ID 17. New factory
instances use `stage-clip-v1`; imported ClipDist effects without an `effectCore`
keep the legacy processor and are never silently migrated. The imported rack
and effect editor expose the explicit upgrade.

## Signal path

The public controls and their indices are unchanged:

1. Input Gain and Drive feed the pre-clip high-pass at the Tone frequency.
2. The independent ADAA soft clipper applies the symmetry bias and removes the
   bias offset.
3. The Clip Filter, sum low-pass, Mix, high-shelf filters, and Output Gain
   complete the legacy signal path.

At fixed settings the Stage core retains that signal path; its difference is
control motion. Drive, Tone, Symmetry, Mix, Clip Filter, Sum Low Pass, shelf
gain/frequency, Input Gain, and Output Gain all use the existing 20 ms smoothing
constant. The filter and shelf coefficients are interpolated from their current
values rather than stepped. This targets zipper noise during controller and
preset automation without changing the static curve.

The nonlinear stage remains the independent antiderivative-antialiased tanh
clipper introduced for the legacy core. No resampling buffer, oversampling path,
allocation, lock, I/O, or framework call is added on the render thread. The
previous clipped sample is already part of the existing effect state; the new
smoothed-control storage is fixed in `EffectState`.

## Compatibility

- Public control indices 0–9 are unchanged.
- Hidden render selector index 10 appends `0` for the legacy core and `1` for
  `stage-clip-v1`.
- `AudioEffect` stores `effectCore`; preset, snapshot, and AU setting round trips
  carry the selector through `renderValues`.
- The imported rack and effect editor identify the active core and offer an
  explicit upgrade.
- A selector change clears the clip smoothing/filter state so the selected core
  starts deterministically.

## Oversampling decision

No oversampling is added. The Stage core retains the existing ADAA clipper and
has not yet been compared with an oversampled reference or a blind listening
panel. A multi-rate path would add latency and CPU cost before those checks
justify it.

## Automated verification

`Tests/StageClipTests.c` runs under AddressSanitizer and
UndefinedBehaviorSanitizer at 44.1, 48, and 96 kHz. It checks the close static
path against legacy, a smoothed large drive step, rapid automation of symmetry
and filters, finite/bounded output, Panic silence, and eight independent
instances. `Tests/ClipDistAutomationTests.c` and `MainStageEffectAudioTests.c`
continue to cover the legacy core and imported static behavior.

`Tests/EffectPresetTests.swift` checks the Stage Clip core identifier, hidden
selector, factory default, preset round trip, and legacy nil-core behavior. The
Swift test and Apple build have not run in this Linux-only environment.

## Pending qualification

- Blind, level-matched comparison against the legacy core and a documented
  Airwindows clip reference at pinned revisions.
- Alias measurements against a host-rate oversampled reference.
- Release-build CPU, memory, latency, and dropout measurements for one, three,
  and eight instances, including physical iPad testing.

No Airwindows source was copied or adapted for this core.
