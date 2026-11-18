# Frequency-dependent decay qualification

Refs #10, #9 and #247. Matching a processor name, a total tail duration or a
listening result about clicking does not establish matching EQ, decay or release.

`Tools/compare-band-decays.py` reports independent octave-band energy and T20-based
T60 estimates for matched wet impulse responses. For each band it retains both
responses, the estimated time difference and energy-gain difference. It sums
stereo power rather than downmixing, so anti-phase output cannot disappear.
Silent, unsettled/noise-limited, too-short and non-exponential measurements do
not receive an estimated decay. These are diagnostic estimates, not certified
room-acoustics measurements or an automatic parity verdict.

Before collecting references, record app/version, source program/processor,
exact parameters, bypass/active state, routing, mono/stereo layout, sample rate,
block size, input/output gain, tempo, excitation, capture method and hashes.
Use an identical deterministic impulse through each wet-only processor. Declare
excitation-end time in the aligned captures; do not feed musical piano releases
into a reverb-decay estimator or subtract unmatched sampler performances.
Capture enough tail to settle at least 60 dB below its peak. A noisy or truncated
capture is a request for better evidence, not permission to shorten the fit.

Example (private files and resulting JSON stay outside the repository):

```
python3 Tools/compare-band-decays.py reference-wet.wav stagekeys-wet.wav --excitation-end 0.1
```

The generated regression uses analytical exponentially decaying tones at several
frequencies and known gain changes, including anti-phase stereo, plus silence,
truncation, nonfinite input and sample-rate mismatch. It validates the estimator;
it does not validate any proprietary source processor.

Separate gates remain: EQ sweep/transfer response; compressor detector,
attack/release/makeup/mix; predelay and early reflections; stereo routing;
parameter automation; instrument note-off/pedal/resonance behavior; and matched
musical listening. Define acceptance tolerances before tuning a processor.

## Current Nord boundary

The experimental piano conversion still has a fixed 100 ms native release and
omits source decay ladders, release/pedal recordings, damper/resonance semantics
and program effects. The source metadata and a piano audition do not establish
those behaviors. The artist-program renderer remains #247; no new source DSP
match or Sunday-ready claim follows from this measurement tool.
