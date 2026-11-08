# Sunday Keys effect parity investigation

This is a clean-room behavioral investigation. StageKeys does not copy Sunday
Keys code, binaries, presets, samples, or artwork. Static observations identify
likely public frameworks and component boundaries; independently recorded input
and output establish behavior. A similar control layout or dependency name does
not prove an identical algorithm.

## Reference identity and observed architecture

The inspected installed artifact is Sunday Keys for macOS 2.5.2 (build 3367,
bundle `com.sundaysounds.sundaykeys`). Its Mach-O strings and imported Swift
type metadata identify AudioKit and SoundpipeAudioKit components, including
`ChorusDSP`, `DynamicRangeCompressorDSP`, `StereoDelayDSP`,
`TanhDistortionDSP`, `ZitaReverbDSP`, and several filters. App wrapper/type
names include `Compressor`, `Delay`, `Chorus`, `PureVerb`, `Shimmer`,
`HaloShimmer`, `PrimaVerb`, and `SolaVerb`. These are artifact observations,
not evidence that every named DSP is active in every wrapper.

The live effect picker exposes 15 effects: Bitcrusher, Chorus, Compressor,
Delay, Equalizer, Flanger, Gain, Halo Shimmer, Overdrive, Pitch Shifter,
PrimaVerb, Rotor, SolaVerb, Tone, and Tremolo. The existing patch was restored
without confirming any draft changes after inspection.

The artifact also contains build paths for AudioKit, AudioKitEX,
DunneAudioKit, and SoundpipeAudioKit and includes their MIT notices. Public
AudioKit documentation assigns Chorus, Flanger, and Stereo Delay to
DunneAudioKit, and Dynamic Range Compressor, Bit Crusher, Tremolo, pitch,
filters, Tanh Distortion, and Zita-family reverb components to
SoundpipeAudioKit. This narrows candidate implementations but does not prove a
wrapper's active topology or package revision; matched output remains required.

## Observed replacement defaults and controls

| Effect | Observed controls/defaults useful for parity |
| --- | --- |
| Bitcrusher | Mix 100%, bit depth 10, sample rate 5 kHz |
| Chorus | Frequency 0.65 Hz, depth 25%, feedback 20%, gain boost +1 dB, mix 100% |
| Compressor | Input 0 dB, attack 20 ms, release 60 ms, ratio 2:1, threshold -40 dB, dry/wet 0%, output 0 dB |
| Delay | Feedback 30%, rhythmic subdivision, ping-pong on, filter 1 kHz, mix 50% |
| Flanger | Rate 0.2 Hz, depth 50%, feedback 0.8, mix 50% |
| Gain | 0 dB, range -infinity to +6 dB |
| Halo Shimmer | Amount 75%, feedback 66%, size 90%, diffusion 75%, modulation 50%, quality 100%, low cut 100 Hz, tone 66%, dry 100%, wet 20% |
| Overdrive | Drive 96%, low cut 402 Hz, tone 4,877 Hz, mix 40%, boost +2 dB |
| Pitch Shifter | +12 semitones, amount 20% |
| PrimaVerb | Medium Hall, predelay 0%, reflectivity 30%, low cut 100 Hz, tone 20 kHz, quality 100%, chorus 0%, rate 1 Hz, dry 80%, wet 40% |
| Rotor | Slow/brake/fast, dynamic mic, 44/402 rpm, acceleration 2.5, mic position, cabinet model, drive, output |
| SolaVerb | Predelay 20 ms, size 50%, reflectivity 50%, quality 100%, low cut 100 Hz, tone 70%, pitch mod 33%, chorus 20%, rate 1 Hz, dry 80%, wet 40% |
| Tone | Frequency 20 kHz, range 20 Hz to 20 kHz |
| Tremolo | Depth 80%, stereo off, tempo/Hz frequency mode, default subdivision 1/8 |

Equalizer uses a separate graph editor and requires a dedicated capture pass.
The percentage-valued tone/size controls also require sweep measurements before
StageKeys may claim matching tapers.

The confirmed Chorus replacement defaults are now the StageKeys factory
defaults. Existing saved patches retain their stored values.

## Measurement contract

For each effect, record Sunday Keys and StageKeys with the same sample rate,
buffer size, mono/stereo input, input gain, tempo, parameter values, and at least
these probes:

1. impulse and silence for latency, predelay, early reflections, tail, and stereo;
2. logarithmic sine sweep for linear frequency and phase behavior;
3. stepped sine levels for compression, saturation, clipping, and makeup gain;
4. steady sine and noise for LFO rate/depth, pitch movement, and diffusion;
5. automated parameter steps for smoothing and tail preservation;
6. musical piano, organ, pad, and synth excerpts for blinded listening.

Use `Tools/compare-effect-captures.py reference.wav candidate.wav` to record
peak/RMS, gain delta, correlation, gain-aligned error, onset, -60 dB decay,
spectral centroid, and stereo correlation. Preserve the original WAV files and
their SHA-256 hashes with every accepted calibration.

`Tools/CaptureAppAudio.swift` supplies the missing driver-free reference route:
it uses ScreenCaptureKit to record only Sunday Keys' emitted system audio as
48 kHz stereo float PCM in a lossless CAF, converted losslessly to WAV with
Apple `afconvert`. It never overwrites a capture and does not insert a
processor into Sunday Keys. macOS Screen Recording permission is required.
Screen Recording permission was granted on 7 November 2026. A matched
`SK Felt Piano | Room` dry/PrimaVerb pair was captured at 48 kHz with the
fixed MIDI probe. The dry and processed CAF SHA-256 values were respectively
`eecbcf62b0abbcdb22ba18ee38c8da2f680ac2edc143975d0bd31384e2724c9a` and
`9343cc76760c733c304ddc0cdfbe5efbdd0c37018d4ba33a08a3281373f5b709`.
Those private rendered captures remain outside the repository. Their measured
processed tail reached -60 dB after 2.62 seconds versus 0.69 seconds dry; this
is a reference observation, not yet a StageKeys parity verdict.

An effect is not marked matched from control names alone. Release acceptance
requires bounded numeric tolerances, a blinded listening pass, finite output at
extreme settings, click-free automation, and CPU/latency results on macOS and a
physical iPad. Exact bit identity is neither expected nor claimed.

## Next measurements

1. Chorus and Flanger impulse/sine captures to recover delay ranges, LFO shape,
   phase offsets, feedback polarity, and wet/dry law.
2. Compressor stepped-level captures to recover detector topology, knee,
   envelope law, mix convention, and makeup gain.
3. Delay impulses at every subdivision to recover feedback filtering,
   ping-pong routing, and filter taper.
4. PrimaVerb/SolaVerb room-by-room impulses and control sweeps.
5. Halo Shimmer octave accuracy, grain/frame latency, feedback topology,
   diffusion, damping, aliasing, and Quality behavior.
6. Remaining nonlinear, EQ, pitch, rotor, tone, tremolo, and gain passes.
