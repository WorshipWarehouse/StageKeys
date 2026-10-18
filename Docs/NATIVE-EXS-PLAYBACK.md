# Native EXS playback and MainStage processing — 0.28

Version 0.34 adds supported source filter/velocity/key/CC routes, group filter offsets, source level/tuning and velocity-dependent attack to independent EXS conversion. New imports use conversion v3; existing source-backed maps have a protected playback update. See [EXS-SYNTHESIS.md](EXS-SYNTHESIS.md) for active behavior, measured tests and remaining circuit/control-curve limitations. The earlier v2 investigation below describes previous limitations, some of which this update addresses.

## v0.28 envelope and processing update

The native EXS translator now reads the bounded global parameter table and translates the amplitude ADSR controls. Envelope time is `10 * (value / 127)^4` seconds. The real Steinway reference has decay 127 (10 seconds), sustain 0 and release 46 (about 172 ms); v0.27 discarded those values in favor of a flat sustain and a 100 ms base release. Existing group release offsets are added to the source base release. Velocity-dependent attack, envelope curvature, nonzero group attack/decay/sustain offsets, global filter/modulation and exact consolidated-region transitions are still not verified identical.

Import Sounds → **Update Converted Sampler Envelopes** upgrades earlier generated EXS presets using their retained, hash-verified original. It backs up presets/library/setlist, verifies that the generated envelope has not been edited, and changes only the envelope and conversion metadata. Zones, loops, original audio references, rack effects and user patch controls remain intact. Hand-edited envelopes are skipped with an explanation. The previous preset remains in Sampler Backups. This does not rebuild the instrument or render replacement samples.

MainStage processing preview additionally translates Compressor threshold, ratio, attack/release, manual makeup and mix. Native compressor circuit, knee, automatic makeup/release, sidechain and limiter response remain different/unmapped. Stereo Delay **manual-time** presets translate per-channel milliseconds, feedback, cross-feedback, output mix and low/high cuts; the native renderer retains separate channel state. Feedback sums must stay below 0.95. Tempo-sync/note-deviation modes are explicitly unsupported rather than being converted with guessed timings. SilverVerb and ClipDist remain unsupported. Existing supported EQ/Gain/Chorus and processing order remain intact.

Reversed linear Smart Controls now retain reversed ranges and MIDI CC/channel routing. Conflicting saved macro positions remain reported. Processing preview shows effect parameters and source names; MIDI-only key-range/transpose/sustain changes can be applied without an audio effect. Sampler settings display the source envelope values. Library columns now default to Note Range / Type / Timbre / Articulation and retain the user's chosen columns when reopening; active filter choices reset as observed in Sunday Keys. This is incremental UI/DSP parity, not a claim of a complete replica.

Validation adds a generated, looped audio fixture that measures decay to zero sustain and finite release to silence, independent of private samples. Real-source tests verify Steinway decay and exact sample hashes, legacy upgrade backups/map retention and edited-envelope protection. Native delay impulse tests verify independent timing and asymmetric cross-feedback/mix. Existing library/MIDI/rack tests remain in the regression suite.

Mac UI verification: the installed earlier Steinway was upgraded successfully through Import Sounds with its original CAF hash unchanged. Its channel still had the user's SolaVerb. Sampler settings showed 10.000 s decay, 0% sustain and 0.172 s base release. The final processing preview displayed 30% chorus depth, 10% chorus mix and 100% compressor mix correctly. Library column changes survived closing/reopening; Note Range was restored afterward. The ten default suites, three real-source checks, expanded upgrade-preservation test, native delay impulse checks, universal Mac build and mobile simulator build passed. Subjective comparison against MainStage and physical iPad runtime remain unverified.

The EXS parameter identities/time curve were cross-checked against the public [ConvertWithMoss format reference](https://github.com/git-moss/ConvertWithMoss/blob/main/src/main/java/de/mossgrabers/convertwithmoss/format/exs/EXS24Parameters.java) and its [timing calibration notes](https://github.com/git-moss/ConvertWithMoss/blob/main/src/main/java/de/mossgrabers/convertwithmoss/format/exs/EXS24Detector.java). StageKeys implements its own bounded Swift reader; no reference implementation is bundled.

## Native EXS playback

## What now plays

When Apple's EXS loader rejects an instrument, StageKeys can translate a bounded little-endian EXS map directly into its native sampler preset. It reads original sample paths, zone/root keys, velocity ranges, tuning, gains, pan, loop extents and group conditions. Original audio files are copied byte-for-byte; no recorded replacement, normalization, sample slicing or sample-rate conversion is created.

Groups use independent native sample layers with note/velocity gates and controller ranges. Groups sharing a controller condition share one playback bank; the Steinway’s 20 logical groups use two banks, with the host root node retained separately. Sustain-selected dry/pedal groups are active processing, not metadata annotations. Current controller values survive branch graph changes; panic resets sustain. FX-only racks and older snapshots retain the instrument’s native group selection. The native group program is embedded in the managed AUPRESET and retained when re-imported into StageKeys, including on the shared mobile code path.

The installed modern Steinway Grand Piano 2 fixture that failed the system EXS loader now translates 224 zones and 20 logical groups into two playback banks. A real original-sample group renders finite nonzero audio. A separate generated audio test verifies exclusive dry/pedal CC64 selection. The actual import API also succeeds, and the copied consolidated CAF has the identical SHA-256 as the original; the EXS source is unchanged. This does not establish exact MainStage fidelity for the complete instrument.

## Explicit EXS limitations

Global EXS parameter decoding remains incomplete. The native translation uses the supported source amplitude ADSR values with an unfiltered signal and disables unrelated template vibrato. Embedded channel-strip overrides of instrument defaults still require separate translation. Group release offsets use a millisecond approximation. Consolidated attack/loop-tail extents are combined into a continuous native region; the source split-region transition algorithm is not verified identical. Saved endpoints beyond the original audio length are bounded and reported. These differences are saved in Import Notes, and the unmodified original EXS is retained.

Unsupported reverse, one-shot/unpitched zones, loop crossfades/tuning/release-to-end behavior, alternate loop direction, output routing, round robin, release-trigger groups, crossfades and unsupported selection modes are rejected rather than silently flattened. Native import limits and selected-root confinement apply.

## MainStage workflow

1. Import Sounds → Import a MainStage Patch retains the source and shows the compatibility report.
2. Import Referenced Sampler Instruments selects the EXS instruments named by that report from a user-selected instrument/sample root. Only those instruments are imported into MainStage Samplers; duplicate filename matches require a narrower folder. MainStage is never launched.
3. Add a sampler sound to a module. In Sound Settings → Settings, Preview MainStage Processing selects a retained source channel.
4. Review supported effects and limitations, then Apply Supported Processing to the editor draft. Existing rack effects/branches stay intact; source effects/macros are appended. Supported source key range, transpose and sustain filter are staged too. Save or discard using the normal editor workflow.

Channel EQ frequencies/gains/Q/band flags, simple Gain, and Chorus rate/intensity/mix have native translations. Native filter slopes, EQ output handling and chorus DSP are not verified identical to Apple's processors. Source processor bypass flags are not independently decoded; preview processors are enabled and the UI explicitly requires review. Unknown effects are reported, not replaced with defaults. This remains a partial processing import, not automatic full-patch conversion.

Smart Control archives are decoded as bounded property-list data without instantiating archived classes. Supported linear mappings to translated effect parameters become native macros, including valid MIDI CC/channel information. Unsupported targets, scales and saved-value encodings remain reported. Generic macro labels and current selected MIDI input routing do not reproduce every original virtual control or port restriction. Saved-value units must match the source effect parameter before a mapping is activated; mismatches are not guessed. Standard binary dry/pedal CC64 selection is verified; finer half-pedal and multi-pedal interaction is not verified.

Incoming non-learned CC events now reach imported instruments. Recognized imported macros update active native processing, including nested racks. MIDI learn, source/channel acceptance and host assignments remain in place. Arbitrary MIDI scripts, source arpeggiators/sequencers, bus routing, private synthesizers and the complete channel-strip state remain unfinished.

## Mac UI verification, October 16, 2026

The v0.27 packaged app was verified after unlocking the Mac. Import Sounds archived the real Two Pianos source and imported its referenced Steinway into MainStage Samplers using the native folder chooser. The library displayed one playable Steinway with accessible conversion notes. The imported preset referenced one CAF whose SHA-256 matched the original audio exactly.

Sound Settings exposed both retained source channels. The first channel's preview displayed Equalizer and Chorus plus the unsupported-processing warnings in a scrollable popover. Applying supported processing added both effects to the editor draft; Discard restored the existing sound. Cancelling the library added no module. The saved setlist JSON remained semantically identical to its backup throughout this walkthrough. This validates the UI workflow, not subjective sonic parity or physical iPad performance.

## iPad architecture and verification

The installed Sunday Keys Mac binary imports AVAudioUnitSampler, AVAudioEngine and AVAudioFile. Its downloaded native catalog refers to sampler AUPRESET instruments and audio files. Sunday Sounds documents a separate locally downloaded library for its standalone iPad/Mac app. Its precise iPad binary implementation, cache/streaming policy and full memory behavior were not inspected or proven.

StageKeys uses the same public Apple sampler API family on Mac and mobile, with app-owned effects, MIDI and group selection. Real-time Mac converted instruments use resident samples to avoid the reproduced streaming-path attack impulses; other live sound types retain the system default. Faster-than-real-time tests explicitly use resident samples. See [SAMPLER-ATTACK.md](SAMPLER-ATTACK.md). iPhone/iPad compilation is checked, but a physical iPad memory/latency test is still required, especially for large consolidated files and many groups.

References: [Apple sampler API](https://developer.apple.com/documentation/avfaudio/avaudiounitsampler), [Sunday Sounds library storage](https://support.sundaysounds.com/article/3169-how-much-storage-space-does-the-sunday-keys-app-need), [MIT EXS layout reference](https://github.com/matt-allan/renoise-exs24). The Swift decoder is independently written; reference attribution is retained in Licenses/EXS-Parser-MIT.md. No proprietary samples, catalogs or source patches are bundled or committed.
