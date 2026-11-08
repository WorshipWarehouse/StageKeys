# Native sound order, amplitude envelope and Mod Filter — #112

This document covers the native sound path. It does not claim that a hosted
Audio Unit, an imported sampler instrument or Sunday Keys uses the same internal
order.

## Documented order

`Synth.c` renders every channel in this order, and `Tests/NativeSoundOrderTests`
guards it:

1. source/sampler gain (`preGain`)
2. compressor (input gain and makeup on the compressed path, Dry/Wet mix; see [COMPRESSOR-RESPONSE.md](COMPRESSOR-RESPONSE.md))
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

MainStage source documents can carry envelope and filter parameters at channel
scope. No observed channel record defines their unit or encoding, so translating
them would be a guess; the converter preserves them as data instead.

- Each field whose name looks like sound shaping (attack, decay, sustain,
  release, cutoff, resonance, filter, ADSR, envelope) is reported individually
  with its archived value, e.g. `Channel_filterCutoff = 2754: retained in the
  source record and not translated`. Numbers keep their archived spelling and
  containers are described by size rather than expanded. The already-translated
  `Channel_filterSustainPedal` is not reported as untranslated shaping.
- The values are stored in `MainStageSourceRecord.retainedShaping`, so they
  survive library persistence, backup and setlist sharing (local paths in values
  and in keys are redacted there) and remain reviewable after the conversion. A
  hostile document is bounded to 32 retained fields, 64 stored fields, 96
  characters per key and 160 per value; a key above the limit is reported with
  its length and skipped rather than truncated or stored, so one oversized field
  cannot invalidate the record and block the import.
- The destination's own envelope and Mod Filter values are never replaced by a
  source value, and the report says so. It also names where each control can
  actually be changed: a converted sampler or hosted Audio Unit owns its
  amplitude envelope, so Sound Settings hides the native envelope for that sound,
  while the Mod Filter is a separate StageKeys stage and stays available there.

A converted sampler instrument's own EXS amplitude envelope and low-pass filter
are translated separately into the generated preset ([NATIVE-EXS-PLAYBACK.md](NATIVE-EXS-PLAYBACK.md));
this section covers only the channel-scope fields that have no supported
mapping. The original source document stays in the patch archive.

## Snapshots

Snapshots capture performance state (levels, pan, effects, imported rack, MIDI
program, plug-in state). They deliberately do not capture the sound-editor
envelope or Mod Filter settings, so recalling a snapshot cannot rewrite how a
sound is shaped. `Tests/ModelTests` asserts the encoded snapshot state contains
no channel-settings keys.

## Transactional sound edits

Confirming a sound edit keeps its audition active until a shaping-only commit succeeds, then replaces the document layer and re-applies the channel's shaping without clearing held notes or pedal ownership. A change that reloads the configured voice or reroutes MIDI releases its old notes first: a different native instrument, external sound or preset, MIDI destination or output channel, imported rack, plug-in state, or sampler attack minimum. Editing the envelope, Mod Filter, EQ, pan, gain or the three audio-effect slots of the same sound reaches the installed voice through `AudioController.configure`. If validation or installation fails, the editor's existing cleanup restores the previous layer; cancelling an edit still uses the normal audition cleanup. `Tests/HeldNoteSoundEditTests` exercises the editor preview/Confirm path with a sustained generated note, then asserts that replacing the instrument installs a distinct, audible voice on the edited channel.

Hosted Audio Unit installs stay asynchronous: the document layer is committed only after the candidate is accepted, and a rejected candidate keeps the previous layer and voice. Panic is still the explicit way to clear a channel.

## Verification

- `Tests/HeldNoteSoundEditTests` (hardware-free, offline render): the editor preview/Confirm path keeps a shaped held note, its pedal and the installed voice, while a replaced instrument stops the retired voice and plays in isolation.
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
