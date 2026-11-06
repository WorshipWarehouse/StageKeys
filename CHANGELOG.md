## Unreleased

- Overlap the native tempo-synced delay's old and new taps for 20 ms across tempo and subdivision changes; the measured worst-case sample step falls from 9.5–11.4× steady at 44.1/48/96 kHz to 1.0×, and the new delay time is reached exactly.

- Add offline, checksummed `.stagekeyssetlist` setlist shares with dependency and collision previews, Save and Load versus Save to Library import, and `stagekeys://setlist-share` links; samples, plug-in state and local source paths are excluded.

- Preflight the successor before removing a live patch, honor Patch Lock in the Store, recall successor pad/tempo/visual mode and keep stopped removal free of instrument loading.

- Validate live resources before publishing previous-session recovery files, retaining the running performance on rejection, and restore the recovered patch’s performed audio tempo.

- Validate patch-locked Tonic Pad resources before live patch/setlist recall, retaining the current pad and performance when the recalled preset is missing or has an unsupported pad map.

- Check known first-patch resources before live setlist open/import so missing samples or unavailable AUs retain the current performance instead of releasing notes and replacing the document.

- Adopt owner-selected MIT licensing for StageKeys-authored code/documentation, retaining existing third-party terms and bundling the project notice on both platforms.

- Honor Patch Lock during setlist file import and recall the imported patch’s Tonic Pad and performed tempo, including the rendered click clock.

- Create independent named local setlists from saved templates without switching the performance; add browser sort/search states and protect preserved library copies when session recovery is required.

- Preserve retired-tail Panic/deadline silence through graph completion and failed-edit rollback, including tails evicted before Panic and later restored from a snapshot.

- Add a saved dynamic MIDI-output range display above the keyboard, with per-sound accessible spans after MIDI effects/transposition and unchanged static input ranges by default.

- Keep level calibration bound to the requested Audio Unit state and the performed tempo; pending/rejected replacements retain their authored state, and probe BPM stays visible when retargeting.

- Bound audio-device inventory property sizes and validate channel-buffer entries before traversal; reject malformed counts and overflow while preserving current routing.

- Add independent saved on-screen keyboard playability and played-note highlighting controls; disabling screen input releases its notes and pedal without silencing hardware MIDI.

- Retain live Tonic Pad root/sound and click intent through unexpected engine configuration/start failures; silence notes while failed, retrigger only after successful recovery, and cancel pending pad recovery on manual Stop.

- Keep the saved click (metronome) choice and the saved output/buffer preferences through an audio-start failure or a device/route change: recovery releases held voices before stopping the engine, restores the click, and re-applies the saved output selection and hardware buffer on the next start instead of erasing them.
- Add a deterministic Store-level startup-recovery matrix (busy output retry, bounded repeated failure, sample-rate/buffer rejection, partial-initialization cleanup, preserved session bytes and injected unplug/sleep-wake route changes) alongside the classifier/retry contract test. Physical AudioBox, competing-app and sleep/wake checks remain outstanding in #110.
- Detect library sounds whose managed file or samples are missing, report them as unavailable while keeping them listed, and offer **Locate Sound File…** to restore the file as an identity-checked managed copy.
- Show one recovery control in the library error state instead of two, and keep **Clear Filters** reachable while the catalog is unreadable.
- Report a saved sound catalog that could not be read as a recoverable error state inside the library modal — with the recovery action beside the results — instead of the sample-free empty state, so the preserved catalog is not mistaken for a missing install. Search and filter empties now state their own case.
- Keep undeclared tag metadata unknown: blank Category, Type, Timbre, Articulation, Source and Complexity values show and filter as Not Tagged instead of leaking an empty facet option or claiming authored provenance, both in the browser and when personal source metadata is loaded.
- Canonicalize facet values (fixed Note Range order, collapsed repeats and blanks) so facet options, matching and ordering stay deterministic.
- Define the release palette, readable type floor and hit-target minimums once in `StageA11y`, render them from `StageTheme`, and raise every 8–10 pt label in the mixer, transport, editors, MIDI Learn, import and snapshot surfaces to the 11 pt minimum.
- Darken the piano octave marker from a measured 2.74:1 to 5.26:1 and move the fader `−∞` label off `.tertiary`, with the contrast pairs recorded in `Docs/ACCESSIBILITY.md` and asserted by a gated test.
- Add patch-level Play In/Hear In direction (nearest, up, down) and an explicit ±2 octave shift; the stored transposition stays the single playback value and older setlists keep theirs without migration.
- Apply patch transposition to authored Easy Chord and Sequencer output as a stateless offset, so repeated key changes cannot drift or rewrite the programming.
- Add a patch tempo lock that shares one live tempo across unlocked patches, with direct BPM entry alongside tap tempo and the stepper; the live tempo is persisted and restored.
- Cover every key pair, octave wrapping, repeated changes, authored mappings, legacy documents and arpeggiator phase across a tempo change.
- Enforce and document the native sound order: source gain → compressor → Mod Filter → EQ → three audio slots → pan → fader. The compressor no longer detects an already EQ-boosted signal.
- Expose Attack/Decay/Sustain/Release and the Mod Filter (min/max cutoff, resonance) in Sound Settings for native sounds, with an explicit explanation instead of inert controls for instrument- or plug-in-owned envelopes.
- Map the mod wheel through one tested exponential filter taper and clamp non-finite or out-of-range modulation.
- Report retained MainStage envelope/filter parameters that are not translated instead of leaving a destination default unexplained; snapshots still exclude sound-editor shaping.
- Show the Program Change opt-in in Patch Settings with an explicit `Program N` label, the raw MIDI 0–127 value and a caption explaining the 1–128 numbering some keyboards use, so the off-by-one is discoverable where the mapping is set.
- Assign one unclaimed explicit number when the opt-in is enabled instead of reusing a value another patch already claims.
- Add a standalone metronome engine with two synthesized click sounds, independent level, beat/downbeat velocities, accent patterns, subdivisions and master-follow; the click now bypasses the shared hall reverb.
- Persist every metronome control in `settings.json`, keep older files readable and refuse out-of-range saved values at launch.
- Cover click timing at 44.1/48/96 kHz, irregular block splits, mid-beat tempo changes, long runs, presets and settings round trips.
- Let the hosted Audio Unit editor expand an oversized plug-in view beyond the collapsed sheet cap and collapse it again, without offering the control when it would reveal nothing or when the window is already the limit.
- Report a blocked, unavailable or slow Audio Unit inside the editor with that state's own remedy instead of an open-ended loading message; a timeout offers Retry, a block offers Allow and Retry, and an uninstalled plug-in says so immediately.
- Label every generic plug-in control for assistive technologies with its parameter name and formatted value, and stop the visible name/value text from being announced twice.

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
