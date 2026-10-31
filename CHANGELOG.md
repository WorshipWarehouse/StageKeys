## Unreleased

- Enforce and document the native sound order: source gain → compressor → Mod Filter → EQ → three audio slots → pan → fader. The compressor no longer detects an already EQ-boosted signal.
- Expose Attack/Decay/Sustain/Release and the Mod Filter (min/max cutoff, resonance) in Sound Settings for native sounds, with an explicit explanation instead of inert controls for instrument- or plug-in-owned envelopes.
- Map the mod wheel through one tested exponential filter taper and clamp non-finite or out-of-range modulation.
- Report retained MainStage envelope/filter parameters that are not translated instead of leaving a destination default unexplained; snapshots still exclude sound-editor shaping.
- Show the Program Change opt-in in Patch Settings with an explicit `Program N` label, the raw MIDI 0–127 value and a caption explaining the 1–128 numbering some keyboards use, so the off-by-one is discoverable where the mapping is set.
- Assign one unclaimed explicit number when the opt-in is enabled instead of reusing a value another patch already claims.
- Add a standalone metronome engine with two synthesized click sounds, independent level, beat/downbeat velocities, accent patterns, subdivisions and master-follow; the click now bypasses the shared hall reverb.
- Persist every metronome control in `settings.json`, keep older files readable and refuse out-of-range saved values at launch.
- Cover click timing at 44.1/48/96 kHz, irregular block splits, mid-beat tempo changes, long runs, presets and settings round trips.

## 0.21.0

- Recreate PrimaVerb's observed Settings, Character, Modulation and Output layout with seven named room sizes, inline knobs, output faders and power control.
- Add functional Quality and zero-Hz Chorus Rate controls; keep nine-value legacy presets compatible without rewriting stored settings.
- Decorrelate the right wet reverb tank while preserving the dry attack and level.
- Verify stereo impulse behavior, old-preset persistence, real piano playback and live sample identity. Exact Sunday reverb DSP and predelay scaling remain unverified.

## 0.20.0

- Preserve sampler instruments across effect graph rebuilds and channel installs, fixing imported patches becoming the default sine tone.
- Preserve newly created parallel samplers and plain-audio sample references; make omitted full-keyboard range defaults explicit on reload.
- Track only owned samplers to avoid activating audio input; give the Mac app enough process-local file handles to stream large instruments under GUI launch limits.
- Verify live source fundamentals, upper harmonics, hot-swaps and both real piano mappings through the production Store/MIDI path.
- Correct reverb predelay with a separate preallocated input delay; keep dry attacks unchanged and clear the delay on panic.
- Fit all five compressor columns using compact controls.

## 0.19

- Verify native Felt Piano against its source state, sample hashes and rendered soft/medium/hard notes.
- Restore supported sampler cutoff and velocity controls; remove unrelated generic-template vibrato.
- Translate modern Delay devices and add backed-up, hash-checked native preset repair tools.
- Add observed Felt Piano Room voicing using the existing private instrument.
- Honor channel compressor input gain, ratio and dry/wet for imported instruments and built-in sounds.
- Match the five-column compressor layout and allow horizontal scrolling on narrow screens.
- Use resident samples for Mac offline fidelity checks while retaining normal real-time streaming.

# 0.4.0

- Fixed stable MIDI hot-plug, idempotent startup, named device status, per-source/channel note identity and unplug/pedal cleanup. Alesis Prestige actual note/pedal input and audible playback verified.
- Added Primary/Secondary MIDI source/channel selection, velocity limits and Plug and Play Defaults.
- Preserved Mac hardware playback in the background and added automatic audio route recovery.
- Refined toolbar/master/channel/fader/Notes/layer geometry and native editor sizing.
- Implemented all 15 synth audio-effect types with parameter editors and tempo-related controls; independent DSP approximations.
- Added three serial native effect slots for compatible imported/AU sources.
- Expanded MIDI styles, 128-step velocity grids, octave Blend and absolute chord/sequence mappings.
- Added snapshot FX/MIDI/pan/modulation/tonic state and effect-replacement propagation.
- Added audio output/buffer settings and semitone channel transpose.
- Migrated v1–v3 setlists to v4 with backup; persisted last selection/mode.

Full 1:1 UI/behavior/DSP parity remains ongoing. See PARITY-STATUS.md.

# 0.3.0

- Matched more of the inspected rack geometry, IBM Plex typography, sidebar, channel slots and keyboard workspace.
- Added an 88-key piano and full layer range/reorder editor.
- Added working synth envelope, voice limit, filter, eight-band EQ, compressor and fader-bound controls.
- Added working chord, octave, arpeggiator and sequencer MIDI processing with channel-scoped note-off/panic.
- Added user audio/bank/sampler-preset import, sample relinking, native AU instruments, plug-in state and instrument interfaces.
- Added external MIDI destinations and a virtual output for MainStage/Ableton or other hosts; native host-patch opener on Mac.
- Added five-line aligned snapshot notes and persistent global preferences.
- Migrated version-1/2 setlists to version 3 with original-file backup.
- Added channel DSP, MIDI effects/output, sampler/preset, third-party AU and production performance-flow tests.

Full Sunday Keys UI/DSP parity and VST hosting remain outstanding. Free Sunday Sounds packs are excluded from redistributable artifacts.
