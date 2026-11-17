# Native channel compressor response — #10

This record covers one bounded slice of [#10](https://github.com/WorshipWarehouse/StageKeys/issues/10): the native channel compressor's **detector, input gain, makeup, Dry/Wet mix and bypass**, with deterministic measurements. It does not claim MainStage parity, and it does not address the issue's EQ bandwidth/Q conversion or SilverVerb/ClipDist/delay work. #10 remains open.

## Where it sits

The native sound path is source/sampler gain → compressor → Mod Filter → eight-band EQ → three audio-effect slots → pan → fader, as documented in [NATIVE-SOUND-ORDER.md](NATIVE-SOUND-ORDER.md). Each channel is mono until pan, so there is no per-channel stereo linking here. A hosted Audio Unit or imported sampler instrument runs its own internal processing and is not described by these measurements.

## Semantics

- The detector follows the peak of the **input-gain scaled** channel signal. Its attack and release are one-pole coefficients, `1 - exp(-1 / (rate × seconds))`, recomputed from the sample rate when the settings change. The configured times are 63% time constants of the linear detector.
- Input gain (−24…+24 dB) belongs to the compressed path and its detector. It is not an output gain.
- Makeup gain (−24…+24 dB) is applied to the compressed path only.
- Dry/Wet Mix crossfades the post-source-gain dry signal with the compressed path. **0% is a true bypass**: it is numerically identical to switching the compressor off, and neither input gain nor makeup reaches the dry signal. 100% carries the compressed path with its input and makeup gain.
- Switching the compressor off, or switching it back on, clears stored detector gain reduction. Parameter edits while it is enabled retain detector state, so dragging a control does not restart the envelope.
- Threshold −60…0 dB, ratio 1…20, attack 0.001…1 s and release 0.01…3 s match `ChannelSettings.validate()` and the compressor controls.

This changes two previously observable behaviors:

- Mix 0% used to apply makeup gain to the mixed output, so "fully dry" could be up to +24 dB louder. It is now an exact bypass.
- With a partial mix, makeup gain used to lift the dry portion as well. It now belongs to the compressed portion only.

The built-in felt-room voicing uses Mix 68% with +3 dB makeup, so its overall level is marginally lower than before this change. No stored setting is rewritten and no migration is required.

## Measured behavior

Method: a deterministic, sample-free sustained native voice (the second built-in instrument) through a short custom envelope and a 0.2 performance fader, velocity 0.8. Each compressor channel is compared with an identical uncompressed engine rendering the same voice and command sequence; values are energy ratios in dB. Steady state settles for 0.75 s and is measured over 0.5 s. Transient steps use 5 ms measurement blocks.

Environment: Ubuntu 24.04, gcc 13.3.0, `-O2`, plus an AddressSanitizer/UndefinedBehaviorSanitizer build. Apple's CoreMIDI headers are unavailable there, so a local header shim supplied only the MIDI event types used by `Synth.c`; the shim is not committed and no MIDI path is exercised by this test. The macOS `xcrun clang` suite and Xcode builds were not run in this environment.

### Steady-state gain transfer

Input-gain and makeup columns are set explicitly; all other cases use 0 dB unless stated.

| Case | 44.1 kHz | 48 kHz | 96 kHz |
| --- | --- | --- | --- |
| Below threshold (threshold 0 dB, ratio 20) | +0.00 dB | +0.00 dB | +0.00 dB |
| Ratio 1 (threshold −60 dB) | +0.00 dB | +0.00 dB | +0.00 dB |
| Threshold −60 dB, ratio 20 | −34.42 dB | −34.41 dB | −34.42 dB |
| Threshold −60 dB, ratio 2 | −18.16 dB | −18.15 dB | −18.16 dB |
| Threshold −60 dB, ratio 20, input +12 dB | −33.82 dB | −33.81 dB | −33.82 dB |
| Below threshold, makeup +6 dB | +6.00 dB | +6.00 dB | +6.00 dB |
| Threshold −60 dB, ratio 20, mix 0%, makeup +6 dB, input +12 dB | 0.00 dB | 0.00 dB | 0.00 dB |
| Threshold −60 dB, ratio 20, mix 0%, makeup −24 dB | 0.00 dB | 0.00 dB | 0.00 dB |
| Threshold −60 dB, ratio 20, mix 50%, makeup +6 dB | −5.70 dB | −5.70 dB | −5.70 dB |
| Threshold −60 dB, ratio 20, mix 100%, makeup +6 dB | −28.42 dB | −28.41 dB | −28.42 dB |

The 12 dB input-gain case moves the output by +0.60 dB, which is `12 × (1 − 1/ratio)` = 12/20: the detector converts almost all of the added input level into reduction. Before this change, the same case measured −33.82 dB **but** the Mix 0% cases measured +6.00 dB and −24.00 dB respectively, because makeup gain was applied to the dry signal.

### Attack and release

| Setting | 44.1 kHz | 48 kHz | 96 kHz |
| --- | --- | --- | --- |
| Attack 50 ms, time to 63% of settled reduction | 25.1 ms | 25.0 ms | 20.0 ms |
| Attack 100 ms, same criterion | 45.1 ms | 40.0 ms | 30.0 ms |
| Release 200 ms, time to 63% toward the new settled reduction | 215.5 ms | 215.0 ms | 215.0 ms |

The attack's dB-domain 63% point arrives before the configured constant: the detector is a one-pole on linear amplitude, reduction only begins once the detector crosses the threshold, and the dB curve is steep immediately after that crossing. The regression therefore also requires that doubling the attack setting approximately doubles the measured point (measured ratio 1.80 / 1.60 / 1.50, allowing for 5 ms blocks and the threshold-crossing portion). Release starts above the threshold between two levels, so its 63% point tracks the setting closely.

### Bypass state

After 0.75 s of compression, switching the effect off, 0.75 s of silence, and switching it back on:

| Measurement window | Before | After |
| --- | --- | --- |
| 20–120 ms after re-enable, 44.1 kHz | −2.53 dB | +0.02 dB |
| 20–120 ms after re-enable, 48 kHz | −2.58 dB | +0.02 dB |
| 20–120 ms after re-enable, 96 kHz | −2.27 dB | +0.02 dB |

A negative value means the re-enabled channel was quieter than an identical channel that was never bypassed; its stale detector was still reducing gain. The first 20 ms are excluded because sub-threshold residual state changes the steepest part of the dB curve without being audible reduction. The regression compares 20–120 ms and requires the difference to stay below 0.1 dB.

### Block invariance

Rendering the same compressor for 0.5 s with uniform 256-frame blocks and with a repeating 1/7/64/255/511-frame split produces the same accumulated energy within 1e-6 relative, at all three rates. Compressor state and limiting are per sample and do not depend on host block boundaries.

## Regression

`Tests/CompressorResponseTests.c` is in the default native C gate (`Tests/test-library.sh`) and the AddressSanitizer/UndefinedBehaviorSanitizer suite (`Tests/test-reverb.sh`). It uses generated signal only and needs no audio hardware, private content or Audio Unit.

```
python3 Tests/run-local-library.py . /private/tmp/stagekeys-compressor
Tests/test-reverb.sh
python3 Tests/test-library-gate.py .
```

## Limits

- Synthetic native voice only. No listening test, no physical output, no measured CPU or latency, and no private library content.
- Not a MainStage comparison. The detector is a peak follower without a knee, sidechain, lookahead, program-dependent release, automatic makeup or limiter circuit, and this change does not establish that its transfer, transient shape or distortion matches Apple's compressor.
- No stereo linking, because the channel is mono before pan; multi-output/multi-channel interaction remains open with the routing issues.
- Hosted Audio Units, imported sampler processing and source-effect translation are unaffected by this change and unverified by it.
- Attack/release values are the linear detector's 63% constants; the measured dB-domain attack point is earlier, as recorded above.
- #10's EQ bandwidth/Q conversion and SilverVerb, ClipDist and delay matching, and all real-reference/hardware qualification remain outstanding.
