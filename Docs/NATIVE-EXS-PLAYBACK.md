# Native EXS playback and MainStage processing — 0.27

## What now plays

When Apple's EXS loader rejects an instrument, StageKeys can translate a bounded little-endian EXS map directly into its native sampler preset. It reads original sample paths, zone/root keys, velocity ranges, tuning, gains, pan, loop extents and group conditions. Original audio files are copied byte-for-byte; no recorded replacement, normalization, sample slicing or sample-rate conversion is created.

Groups use independent native sample layers with note/velocity gates and controller ranges. Groups sharing a controller condition share one playback bank; the Steinway’s 20 logical groups use two banks, with the host root node retained separately. Sustain-selected dry/pedal groups are active processing, not metadata annotations. Current controller values survive branch graph changes; panic resets sustain. FX-only racks and older snapshots retain the instrument’s native group selection. The native group program is embedded in the managed AUPRESET and retained when re-imported into StageKeys, including on the shared mobile code path.

The installed modern Steinway Grand Piano 2 fixture that failed the system EXS loader now translates 224 zones and 20 logical groups into two playback banks. A real original-sample group renders finite nonzero audio. A separate generated audio test verifies exclusive dry/pedal CC64 selection. The actual import API also succeeds, and the copied consolidated CAF has the identical SHA-256 as the original; the EXS source is unchanged. This does not establish exact MainStage fidelity for the complete instrument.

## Explicit EXS limitations

Global EXS parameter decoding remains incomplete. The native translation uses an unfiltered amplitude envelope and disables unrelated template vibrato. Group release offsets use a millisecond approximation. Consolidated attack/loop-tail extents are combined into a continuous native region; the source split-region transition algorithm is not verified identical. Saved endpoints beyond the original audio length are bounded and reported. These differences are saved in Import Notes, and the unmodified original EXS is retained.

Unsupported reverse, one-shot/unpitched zones, loop crossfades/tuning/release-to-end behavior, alternate loop direction, output routing, round robin, release-trigger groups, crossfades and unsupported selection modes are rejected rather than silently flattened. Native import limits and selected-root confinement apply.

## MainStage workflow

1. Import Sounds → Import a MainStage Patch retains the source and shows the compatibility report.
2. Import Referenced Sampler Instruments selects the EXS instruments named by that report from a user-selected instrument/sample root. Only those instruments are imported into MainStage Samplers; duplicate filename matches require a narrower folder. MainStage is never launched.
3. Add a sampler sound to a module. In Sound Settings → Settings, Preview MainStage Processing selects a retained source channel.
4. Review supported effects and limitations, then Apply Supported Processing to the editor draft. Existing rack effects/branches stay intact; source effects/macros are appended. Supported source key range, transpose and sustain filter are staged too. Save or discard using the normal editor workflow.

Channel EQ frequencies/gains/Q/band flags, simple Gain, and Chorus rate/intensity/mix have native translations. Native filter slopes, EQ output handling and chorus DSP are not verified identical to Apple's processors. Source processor bypass flags are not independently decoded; preview processors are enabled and the UI explicitly requires review. Unknown effects are reported, not replaced with defaults. This remains a partial processing import, not automatic full-patch conversion.

Smart Control archives are decoded as bounded property-list data without instantiating archived classes. Supported linear mappings to translated effect parameters become native macros, including valid MIDI CC/channel information. Unsupported targets, scales and saved-value encodings remain reported. Generic macro labels and current selected MIDI input routing do not reproduce every original virtual control or port restriction. Saved-value units must match the source effect parameter before a mapping is activated; mismatches are not guessed. Standard binary dry/pedal CC64 selection is verified; finer half-pedal and multi-pedal interaction is not verified.

Incoming non-learned CC events now reach imported instruments. Recognized imported macros update active native processing, including nested racks. MIDI learn, source/channel acceptance and host assignments remain in place. Arbitrary MIDI scripts, source arpeggiators/sequencers, bus routing, private synthesizers and the complete channel-strip state remain unfinished.

## iPad architecture and verification

The installed Sunday Keys Mac binary imports AVAudioUnitSampler, AVAudioEngine and AVAudioFile. Its downloaded native catalog refers to sampler AUPRESET instruments and audio files. Sunday Sounds documents a separate locally downloaded library for its standalone iPad/Mac app. Its precise iPad binary implementation, cache/streaming policy and full memory behavior were not inspected or proven.

StageKeys uses the same public Apple sampler API family on Mac and mobile, with app-owned effects, MIDI and group selection. Real-time Mac playback retains the system sampler streaming default; faster-than-real-time tests explicitly use resident samples. iPhone/iPad compilation is checked, but a physical iPad memory/latency test is still required, especially for large consolidated files and many groups.

References: [Apple sampler API](https://developer.apple.com/documentation/avfaudio/avaudiounitsampler), [Sunday Sounds library storage](https://support.sundaysounds.com/article/3169-how-much-storage-space-does-the-sunday-keys-app-need), [MIT EXS layout reference](https://github.com/matt-allan/renoise-exs24). The Swift decoder is independently written; reference attribution is retained in Licenses/EXS-Parser-MIT.md. No proprietary samples, catalogs or source patches are bundled or committed.
