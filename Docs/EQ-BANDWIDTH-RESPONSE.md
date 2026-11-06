# EQ response and bandwidth/Q conversion — #10

This record covers one bounded slice of [#10](https://github.com/WorshipWarehouse/StageKeys/issues/10):
the native eight-band channel EQ's **peaking gain transfer and displayed
octave bandwidth**, with measured frequency-response evidence at 44.1/48/96 kHz.
It does not claim MainStage parity. Shelf slope matching, high-pass/low-pass
slope choices, the issue's SilverVerb/ClipDist/delay work and all real-reference
qualification remain outstanding, and #10 stays open.

## What the control means

`EqualizerEditor` shows peaks 1–4 with a **Bandwidth** knob in octaves, matching
the observed reference layout (`Docs/DEEP-UI-AUDIT.md`). The saved model keeps
**Q** (`EQBand.q`), and `EQBandwidth` converts between the two with the analog
constant-Q relation `1/Q = 2·sinh(ln2/2·BW)`. That is the same conversion the
felt-room voicing and the Audio Unit bandwidth bridge use.

RBJ defines a peaking band's BW between the **midpoint (gain/2) gain
frequencies**. Feeding the stored Q directly into `alpha = sin(w0)/(2Q)` is the
analog prototype; after the bilinear transform the rendered midpoint width
shrinks toward Nyquist. At 12 kHz with a 44.1 kHz rate the old mapping rendered
**0.580 octaves for a displayed 1.00** — a 42% error, audible as a peak that is
much narrower than the editor says.

## Change

`Synth.c` now realizes peaking bands with RBJ's BLT form:

```
alpha = sin(w0) · sinh( ln(2)/2 · BW · w0/sin(w0) )
```

where `BW` is the displayed width derived from the stored Q. Peaks therefore
render the width the editor shows at every centre and rate. Shelves, high pass
and low pass keep their existing coefficient math, and the stored model, UI,
presets and Audio Unit bridge are unchanged.

Because the conversion is now applied at render time, previously saved high-Q,
high-frequency peaks are slightly wider. For example the felt-room voicing's
5.4 kHz band (Q 0.73) widens by roughly 9% at 48 kHz. No value is rewritten; the
same saved Q now means its displayed width.

## Measured before/after

Method: impulse through the shared `equalizer()` path (the effects-engine
Channel EQ uses the same coefficients as the channel EQ), magnitude by DFT,
midpoint crossings solved by bisection. +12 dB peak, 44.1/48/96 kHz.

| Centre | Rate | Requested | Before | After | Before error |
| --- | --- | --- | --- | --- | --- |
| 4 kHz | 44.1 kHz | 1.00 oct | 0.944 | 0.996 | -5.6% |
| 8 kHz | 44.1 kHz | 1.00 oct | 0.792 | 0.989 | -20.8% |
| 12 kHz | 44.1 kHz | 1.00 oct | 0.580 | 0.997 | -42.0% |
| 12 kHz | 44.1 kHz | 2.00 oct | 1.154 | 1.974 | -42.3% |
| 8 kHz | 48 kHz | 1.00 oct | 0.822 | 0.989 | -17.8% |
| 12 kHz | 48 kHz | 1.00 oct | 0.635 | 0.991 | -36.5% |
| 12 kHz | 48 kHz | 2.00 oct | 1.256 | 1.940 | -37.2% |
| 12 kHz | 96 kHz | 1.00 oct | 0.896 | 0.993 | -10.4% |
| 12 kHz | 96 kHz | 2.00 oct | 1.761 | 1.945 | -12.0% |

Band centre gain is unchanged at +12.00 dB (within 0.05 dB) for boosts and
-12.00 dB for cuts at every rate.

Residual error after the change is within 1.1% for 0.5- and 1-octave bands and at
most 4.1% for a 2-octave band at 8 kHz/44.1 kHz, where the upper midpoint edge
approaches Nyquist and the bilinear transform is no longer symmetric. Low
centres (100 Hz, 1 kHz) stay within 0.4% at all three rates.

## Regression

`Tests/EQResponseTests.c` drives the engine and asserts:

- unity response for 0 dB bands (no colour when the EQ is effectively flat);
- ±12 dB centre gain within 0.05 dB;
- midpoint octave width within 2% for 0.5/1-octave bands and 6% for 2-octave
  bands (measured worst cases 1.1% and 4.1%), at 100/1000/4000/8000/12000 Hz and
  44.1/48/96 kHz;
- boost/cut symmetry and monotonic width versus Q at 10 kHz;
- high-pass and low-pass corner gain and 12 dB/octave slope;
- shelf plateau and unity ends;
- finite, bounded output for every band at ±24 dB with Q 0.1 and 10.

It runs in the default native C gate and in the `Tests/test-reverb.sh`
ASan/UBSan suite.

## Limits

- No MainStage capture was compared. This measures StageKeys' own rendered
  response against its own displayed conversion; it does not establish that
  MainStage's Channel EQ uses the same Q, bandwidth definition or shelf slope.
- Shelves still use `alpha = sin(w0)/(2Q)` as a slope proxy. The reference
  display has no shelf bandwidth control, but slope behavior is unverified.
- Q remains the stored value. At fixed Q the editor displays the same octave
  width as the centre frequency changes, and the native peaking filter targets
  that width across the measured frequency range.
- Only the native engine was measured. Hosted Audio Units, imported samplers and
  the AU bandwidth bridge are unchanged and unverified here.
- Environment: Ubuntu 24.04, gcc 13.3.0. A local CoreMIDI header shim was needed
  to compile `Synth.c`; it is not committed and no MIDI path is exercised. macOS
  `xcrun clang`, Xcode builds and the Swift suite were not run.

The corrected bisection passed on macOS with AddressSanitizer and UndefinedBehaviorSanitizer. The After column uses that run.
