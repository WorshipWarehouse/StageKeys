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
