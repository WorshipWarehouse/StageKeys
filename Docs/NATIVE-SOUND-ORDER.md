# Native sound order, amplitude envelope and Mod Filter — #112

This document covers the native sound path. It does not claim that a hosted
Audio Unit, an imported sampler instrument or Sunday Keys uses the same internal
order.

## Documented order

`Synth.c` renders every channel in this order, and `Tests/NativeSoundOrderTests`
guards it:

1. source/sampler gain (`preGain`)
2. compressor (with input gain, mix and makeup)
3. Mod Filter (low-pass, `filterMin`→`filterMax`, resonance)
4. the eight-band EQ
5. three serial audio-effect slots
6. stereo pan
7. performance fader

The compressor therefore detects the source level. An EQ boost or a Mod-Filter
sweep cannot push the compressor past its threshold, which is the behaviour the
manual describes and the reason this order is a regression test rather than a
preference.

Pan is the last stereo stage; the fader scales both sides afterwards. Before
this change the compressor ran after the EQ, which made an EQ boost reduce the
output instead of raising it.

## Amplitude envelope

Attack, Decay, Sustain and Release are exposed in Sound Settings for sounds that
run on the native synth path. The engine applies them per channel through
`sk_envelope`, and the values are validated (`attack`/`decay` 0.001–10 s,
`sustain` 0–1, `release` 0.001–30 s).

A sound whose amplitude envelope belongs to a loaded instrument or a hosted
plug-in does not show editable native values. StageKeys says so instead of
drawing knobs that do not process the sound.

## Mod Filter

`ChannelSettings.cutoff(modulation:)` maps the mod wheel exponentially between
Filter Min and Filter Max, so equal wheel movement sounds even. CC1 and the
on-screen wheel both reach it through `PerformanceStore.updateToneFilters`, and
a hosted Audio Unit is sent the same cutoff and resonance as CC1 plus its own
processing call. Out-of-range or non-finite modulation is clamped.

Filter Min is clamped to Filter Max in the UI so an invalid pair cannot be
saved, and the model still validates the pair.

## Conversion reporting

MainStage source documents can carry envelope and filter parameters that this
converter does not translate. The conversion report now names every retained
key that looks like sound shaping (attack, decay, sustain, release, cutoff,
resonance, filter, ADSR, envelope) and states that the destination keeps its own
values. Nothing is silently replaced with a StageKeys default, and the original
source document stays in the patch archive.

## Snapshots

Snapshots capture performance state (levels, pan, effects, imported rack, MIDI
program, plug-in state). They deliberately do not capture the sound-editor
envelope or Mod Filter settings, so recalling a snapshot cannot rewrite how a
sound is shaped. `Tests/ModelTests` asserts the encoded snapshot state contains
no channel-settings keys.

## Verification

- `Tests/NativeSoundOrderTests` (C, in the default library gate): a post-
  compressor EQ boost must reach the output, the Mod Filter closes and opens,
  maximum resonance stays finite, a long attack is quiet then loud, zero source
  gain is silent with EQ/compressor enabled, and a hard-left pan preserves the
  stereo law.
- `Tests/ChannelSignalOrderTests` (hardware-free): exponential taper endpoints,
  geometric-mean midpoint, clamping of out-of-range and non-finite modulation,
  and envelope/filter validation bounds.
- `Tests/ModelTests`: snapshot state excludes sound-editor envelope and filter
  values.

Not verified here: macOS/iOS builds, the release artifact gates, listening
comparisons, hosted Audio Unit internal order and physical-device behaviour.
