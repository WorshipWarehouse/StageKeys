# Stage Flanger — `stage-flanger-v1`

Status: implemented in Sources/Synth.c, selected by new Flanger instances, with
the original flanger retained for existing patches. Automated correctness passes
on this branch at 44.1, 48 and 96 kHz. Listening, release-build CPU and physical
iPad qualification are not yet recorded.

## Identity and compatibility

Effect ID 8 remains Flanger. The implementation selector is stored in
`AudioEffect.effectCore`. A missing selector selects the legacy processor; an
existing patch, preset, snapshot or imported MainStage flanger is not migrated
silently. New Flanger instances are created with `stage-flanger-v1`. The editor
shows the active core and offers **Use Stage Flanger** for an explicit upgrade.
The hidden core selector is render parameter index 4, appended after the four
public controls, so the public control indices and saved values are unchanged.

## Controls

| Index | Control | Range | Stage mapping |
|---:|---|---|---|
| 0 | Rate | 0.1–10 Hz | LFO frequency, smoothed |
| 1 | Depth | 0–1 | Wet-tap sweep around 1.5 ms; nominally 0–3 ms, clamped at two samples |
| 2 | Feedback | −0.95–0.95 | Signed feedback, soft-limited |
| 3 | Mix | 0–1 | Dry/wet crossfade, smoothed; 0 is exact dry |
| 4 | Core selector | 0/1 | Hidden `stage-flanger-v1` selector |

## DSP design

The Stage core is an independent StageKeys implementation. It reuses
`tap_cubic_capacity`, the already-qualified cubic interpolator shared with Stage
Delay, and does not add a second framework or allocate during rendering.

- A fixed 1.5 ms reference tap feeds the dry side of the comb. The wet tap
  sweeps from nominally 0 to 3 ms around it, passing through the reference
  delay. The relative delay therefore crosses zero without a non-causal read:
  the reference is delayed and the wet tap may be earlier or later than it.
- Both taps are cubic-interpolated and clamped inside the preallocated effect
  history. The wet tap never goes below two samples, so the negative-delay region
  is bounded rather than indexed out of range.
- An engage smoother with a 20 ms time constant fades the comb in and out. Mix 0
  is an exact input bypass with no added latency; once engaged, the reference
  path adds 1.5 ms of latency. This keeps the through-zero topology causal
  without a step when Mix leaves zero. After a reset or core change the comb
  starts disengaged and fades in, so cleared delay taps cannot cause a dropout.
- The right side's LFO is offset by 90° when the engine is rendering a stereo
  side. The two channels share timing but produce a stable, decorrelated comb.
- Feedback is the signed public value, clamped to ±0.95 and passed through
  `tanh` before it is written back. Either polarity remains bounded, and the
  write is independent of the dry gain.
- Rate, depth, feedback and mix use a 20 ms one-pole smoother with an exact snap
  at the target. Abrupt automation therefore does not step the delay time or the
  mix. Mix at zero is an exact dry identity, including while feedback and depth
  are non-zero.
- The effect uses the existing per-slot delay history. It does not allocate,
  lock, log or call platform APIs on the render thread. Panic and channel panic
  clear the delay history, the flanger smoothers and the ready flag; repeated
  Panic is silent.
- The engaged effect has the 1.5 ms reference latency. Mix 0 is a hard dry
  bypass, so an unused flanger slot adds no latency; the 20 ms engage smoother
  prevents a discontinuity when entering or leaving that bypass.

## Verification performed

`Tests/StageFlangerTests.c` runs in the ASan/UBSan suite
(`Tests/test-reverb.sh`) and covers, at 44.1, 48 and 96 kHz:

- exact dry identity at Mix 0 with depth 1 and feedback 0.9;
- finite, bounded stereo output, a non-zero left/right difference and a
  non-zero difference from the retained legacy core;
- both feedback polarities at maximum depth and ±0.95 feedback for ten seconds,
  followed by two independent Panic-and-reset checks;
- rapid rate, depth, feedback and mix automation;
- stepped Mix and depth changes that are smoother on the Stage core than the
  legacy processor, which applies the new value on the next block;
- eight simultaneous instances for ten seconds, finite and bounded.

The test prints delay-storage figures for eight engines: approximately 9.6 MiB
at 44.1 kHz, 9.7 MiB at 48 kHz and 19.3 MiB at 96 kHz, counting the three
per-slot histories each engine preallocates. These are calculated allocation
figures, not measured process resident memory. The sanitizer-suite timing print
is a smoke figure, not release-build CPU evidence.

The local run used GCC with ASan/UBSan on Linux and a temporary CoreMIDI shim
outside the repository. The repository's macOS `Tests/test-reverb.sh` job, Xcode
builds and Swift compilation were not available in this Linux checkout and
remain pending.

`EffectPresetTests` covers factory selection, the legacy selector, validation
and preset round-trips. `Tests/test-library-gate.py` confirms the new C program
is gated.

## Remaining qualification

- Blind listening against the retained core on transient piano, sustained organ,
  bright synth, wide pad and a mono source through a stereo instance.
- Release-build median/worst render time, CPU percentage, resident memory,
  reported latency and dropouts for one, three and eight instances at the
  smallest supported buffer, including 96 kHz.
- Physical iPad thermal and underrun behaviour.
- A measured comparison of the zero-crossing sweep's spectral null against a
  reference implementation. The current test establishes bounded, stable comb
  behaviour, not a reference sound match.

The Stage Flanger is not claimed to be sonically identical to any other product.
