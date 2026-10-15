## Version 0.19

Fixed the live sine-tone regression: effect graph rebuilds now preserve sampler document state and sample references, including parallel branches. Live source-content and real piano tests verify the playback path. Reverb predelay now delays the wet input correctly, and compact compressor controls fit the editor. See [piano fidelity evidence and limitations](Docs/PIANO-FIDELITY.md).

## Version 0.18

Shared-input parallel audio-effect racks, nested audio macros and editors, groove timing after scheduler stalls, and isolated library Audition. See [behavior and verification](Docs/PARALLEL-AUDIO.md).

## Version 0.17

Parallel instrument branches, shared macros, anchored swing timing, editable branch processing and a macOS app icon. See [parallel routing notes](Docs/PARALLEL-ROUTING.md) for verification and remaining differences.

## Version 0.16 — imported timing and nested racks

The local free library now has 488 translated effect instances, including 57 stereo delays, 213 effect macros and nine arpeggiator programs across 213 imported sounds. Imported processing remains separate from the three performance effect slots. Single-branch nested racks retain serial effect order and separate macro scopes; parallel branch processing remains unfinished.

The MIDI editor exposes synced/free rate, gate, hold, repeats, retrigger and velocity controls. Imported delays have separate left/right times and sync modes. Library selection previews keyboard ranges without committing a sound. See [translation details and limitations](Docs/IMPORTED-TIMING.md) before treating imports as equivalent to Live: numeric chooser mappings are inferred, reverb/EQ are approximate, and the scheduler is not sample accurate.

Mac and iOS builds, deterministic timing/impulse tests, production playback and MIDI regressions are verified. Private sound assets remain in the local user library, outside the app and source archives.

The sections below describe earlier releases.

## Version 0.13 — direct Ableton sample-map import

Import Sounds now accepts Live Packs (`.alp`) and sample-based Ableton rack/preset files (`.adg`/`.adv`). Choose the pack directly, or choose an individual preset and its sample folder. The pack importer runs in stages with progress, skips presets already imported and records failures. No Ableton installation, playback capture or resampling is used. The original audio bytes, including FLAC files supplied in packs, are copied unchanged into the managed library.

Supported sample maps retain key/velocity limits, root pitches, sample endpoints, forward sustain-loop positions and active layers at the saved rack-selector setting. Basic amplitude envelope stages and saved level/tuning values are translated. Every distinct mapped root is rendered at an in-range velocity; layers are tested independently before publication. Sample hash checks verify unchanged original files.

These are **sample-map conversions**, not complete Live rack emulations. Live effects, MIDI processing, macro assignments, filter/LFO modulation, envelope curves and some crossfade/loop modes remain untranslated or approximate. Each imported sound exposes Import Notes in the library. Missing samples and silent saved rack selections are reported instead of installed.

The library now follows the observed four-column Category/Type/Timbre/Articulation layout with configurable facets, collection selection, combined search, sorting and explicit Add Sound confirmation. Selecting a row no longer changes the active channel. Original MainStage archive entries remain separate and clearly indicate conversion status. Tags inferred from filenames are provisional rather than Sunday Sounds' authoritative metadata.

Private Sunday Sounds audio stays in the local user library and is excluded from app/source archives. Mac behavior is tested; mobile compilation is verified separately from physical iPhone/iPad playback.

## Version 0.11 — sound import and built-in effects

Import Sounds is available directly from the performance toolbar, main menu and sound browser. Add an audio file, SF2/DLS bank, EXS/AUPRESET instrument with its samples, or a folder of sampler instruments. Imports appear in My Sounds without replacing the current channel. Sound-export controls have been removed; setlist sharing remains available.

The effect picker follows the observed Sunday Keys fifteen-effect catalogue and column order. Every effect is now available for imported instruments as well as StageKeys synth sounds, with three serial slots per channel and all catalogue parameter controls. A registered in-process Audio Unit uses the shared StageKeys DSP with preallocated stereo buffers; no external effect plug-ins are required.

These are original DSP implementations. Catalogue and workflow matching do not establish sonic equivalence to Sunday Keys. Full visual parity, Tonic shimmer DSP, Patch Builder and Flex Routing still need work.

Validation includes all fifteen effect renders, 44.1/48 kHz bypass and delay-tail checks, imported WAV/AUPRESET/DLS playback, serial gain, library-only import persistence, CoreMIDI lifecycle and sanitizer coverage. Testing fixed a Rotor delay-buffer boundary error and a sampler/effect sample-rate mismatch. Private Sunday/Apple sound assets remain local and are excluded from these archives.

## Version 0.10 — patch and settings workflows

Add Patch now opens a sidebar menu, then a named blank-patch dialog or a local patch-library picker. Blank patches contain 15 empty modules. Library copies preserve sound/snapshot content with independent identities and leave the active setlist in place.

Patch Settings now follows the observed card layout and adds -24/+12 dB patch volume adjustment and explicit MIDI program-change assignments. Existing files retain legacy ordinal program changes. New patches default to program change off. Patch volume applies to sound modules and leaves Tonic volume separate. Imported-instrument audio measurements and CoreMIDI integration tests pass.

The main menu now opens inside the app, Settings has wider sidebar navigation, modal headers are centered, and disabled buttons dim. Clicking the Tonic Pad name opens live brightness/shimmer settings. Shimmer remains an octave-layer approximation; full DSP parity, Patch Builder and Flex Routing are unfinished. Mac navigation was inspected; iOS builds compile but physical mobile layouts remain unverified.

Bundled Sunday Tonic sampler mapping is now understood and tested: twelve timbres are selected by velocities 1–12, not normal keyboard velocities. The isolated probe passed 36 note/selector combinations. These timbres have not yet replaced StageKeys' Tonic engine. Downloaded native Sunday app instruments and the converted Base Warm Pad remain local library assets, excluded from the archives.

## Version 0.9 — MainStage sampler capture conversion

StageKeys imports modern MainStage Auto Sampler EXS captures, including long sample filenames that Apple's standalone sampler does not resolve directly. A temporary compatibility copy rewrites references while preserving source files and sample-zone, velocity and loop data. Referenced samples remain confined to the selected folder and are copied into the managed library.

Tools/ConvertMainStageCapture.swift converts batches of captured instruments, checks finite audible playback at requested pitches/velocities, optionally checks sustained loops, and exports portable AUPRESET + Samples folders. Existing sound-library entries are retained; failed captures are reported rather than installed. See [conversion instructions](Tools/README.md).

Sampling freezes the selected instrument/effect sound. It does not reproduce arbitrary synth controls, modulation states, tempo-synced arps or complete multi-channel patches. Conversion of the full ten-volume free library remains ongoing. Private captured samples stay outside the distributed app/source archives.

## Version 0.8 — live channel editing and MIDI Learn

Sound, audio-effect and MIDI-effect editors now audition changes through the live channel. Discard restores the original settings; Confirm saves them. Unconfirmed drafts are excluded from background saves, and stale editor tokens cannot overwrite another patch. Changes that alter note routing release only the affected channel. Hosted AU state is captured for rollback, but third-party plugin window behavior still needs broader verification.

MIDI Learn now supports master level, modulation, sustain, previous/next patch, panic, 15 sound levels and existing snapshots. Button actions trigger once per press, and assigning a button does not execute its action. Sustain combines learned controls with CC64 and the screen pedal; clearing or replacing a learned pedal releases its contribution. Existing sound-level assignments remain compatible. CC1, CC64, CC120 and CC123 retain their fixed routes.

Verification: universal Intel/Apple Silicon Mac build, isolated audio/DSP/model/store tests and real CoreMIDI virtual-source integration tests. The tests include editor preview persistence isolation, Discard, expired tokens, Confirm, button edges and pedal reassignment. Native Mac MIDI Learn navigation was inspected. Physical iPhone/iPad and third-party AU editor rollback remain unverified.

Remaining: precise visual matching across all pages, freely replaceable channel FX A/B, full Flex Routing, sample-accurate sequencing, and native conversion of the ten free MainStage volumes. Cloud/Prime remains excluded. Private imported sounds remain in the local user library and are excluded from the archives.

## Version 0.7 — channel UI and local performance libraries

The Sound Settings editor now follows the observed three-tab layout: FX A: Equalizer, FX B: Compressor, and Settings. The equalizer uses eight colored knob columns with logarithmic frequency, gain and octave-bandwidth controls rather than stacked sliders. Channel Settings groups sustain, MIDI Input Transpose, voice count and fader range alongside sampler volume and pan. Original synth envelopes and mod-filter settings remain available under More Sound Controls. The rack Equalizer uses the same eight-column controls.

MIDI Input Transpose now precedes MIDI effects for both physical keyboard and screen-keyboard input. Patch-wide transpose is applied to MIDI-effect output. This changes chord/sequence lookup behavior to match the reference's explicit channel-setting description; existing presets that relied on post-effect channel transpose may need adjustment.

Export to Library saves a complete reusable sound, including its channel settings, effects, MIDI program and AU state where available. My Sounds can recall this into another module with an independent module identity. Native sound references still point to the managed local sample library; this is not a cross-device sample bundle. The 0.6 sampler bundle exporter remains available for that purpose.

The Setlists browser supports local create/open/search/rename/duplicate and recoverable Trash/restore. The original active setlist remains backed by setlist.json, and local library copies live in Application Support/StageKeys/Setlists. Switching preserves the previous setlist; duplicate regenerates patch, layer and snapshot identities. Corrupt library files are preserved and reported. Current setlists cannot be moved to Trash until another setlist is opened.

Keyboard Layers has direct draggable grips with Move Up/Down context-menu and accessibility actions. Reordering moves the sound together with snapshot levels/states and MIDI assignments. The interaction temporarily silences held notes to avoid hanging voices. Full visual parity, freely replaceable channel FX A/B, live editor audition, complete Flex Routing, advanced MIDI Learn and sample-accurate MIDI sequencing remain unfinished. Cloud/Prime remains excluded.

## Version 0.6 — native sampler interchange and performance controls

The modulation control is now a ridged wheel with continuous drag and held position. It sends CC1 to hosted instruments and external MIDI destinations as well as controlling StageKeys filters. Snapshot fades include compatible FX/pan, modulation, tonic gain and brightness. Tonic root/enabled/shimmer still switch structurally.

The browser separates Sunday Free (MainStage host entries) from Sunday App (privately imported native sampler instruments). On this Mac, 21 already-downloaded Sunday app instruments passed native offline rendering and are installed in the personal library. They require neither Sunday Keys nor MainStage at playback. The three bundled utility presets were not installed as playable instruments because the initial test notes rendered silence; their special note/control maps need separate work.

Import Sound → Import Sampler Library Folder scans a selected folder for up to 256 EXS/AUPRESET instruments and copies their referenced audio. Choose a folder containing both presets and samples. Native sampler rows offer Export on Mac: a new folder contains Instrument.aupreset and Samples. Exported presets work with Apple's AUSampler; moving the folder requires relinking/reimporting. Sunday Keys' own app does not provide a verified direct MainStage patch import route.

The ten free MainStage volumes are still host presets: conversion of their complete synth/effect/MIDI chains remains unfinished. Auto Sampler was opened and configured in a separate scratch concert, but stalled at its first capture note and produced no verified EXS/audio. No captured prototype is labeled or installed as a native free preset. Original user concert files were not edited. MainStage's test output was changed from System Setting to Mac mini Speakers; capture must be stopped before restoring this preference.

Audio output choice now persists by CoreAudio UID on Mac. Missing devices retain the system/default route; device fallback beyond that remains to be hardened. Private Sunday/Apple sound assets are excluded from the app and source archives.

## Version 0.5 local library update

The sound browser now includes persistent My Sounds and Sunday Free collections, searchable by name or volume. Imports remain available when adding sounds to other patches. EXS24 import asks for a sample folder, copies referenced samples into the managed library, and reports Apple sampler compatibility errors.

On the development Mac, all 10 downloaded Sunday Sounds MainStage volumes are installed in the user library (358 patch bundles, including nested variants). These entries are labeled MainStage: they open in MainStage and use StageKeys’ virtual MIDI output. They are not yet native conversions of the full instrument/effect chains. No Sunday Sounds or Apple samples/presets are included in the distributed app/source archive. Installed EXS base instruments must not be mistaken for the complete Sunday Sounds presets.

Snapshot transitions now interpolate compatible effect parameters and pan, with structural effect/MIDI changes applied at the beginning. Cloud and Prime workflows are outside the current scope. Full visual/functional parity and native rendering of the free preset collection remain unfinished.

# StageKeys 0.4

Native keyboard performance app for macOS 13+, iPadOS/iOS 16+. The Mac build is universal (Apple Silicon and Intel), locally ad-hoc signed and not notarized. Extract StageKeys-Mac.zip and open StageKeys.app. Audio starts automatically; play the on-screen keyboard or a connected MIDI keyboard. The speaker button opens Audio settings.

The included Soft Keys, Warm Pad and Glass Bells sounds are independently synthesized. Sunday Sounds sample libraries, free patch packs, artwork and executable code are excluded from the app/source distribution. IBM Plex Sans is included under its accompanying OFL license.

## New in 0.4

MIDI plug-and-play is verified with the user's Alesis Prestige: connected status, actual notes/releases/pedal received, and audible playback confirmed. Stable hot-plug connections replace reconnect/Panic on every notification. Named connected/offline devices, Primary/Secondary routing, velocity limits and Plug and Play Defaults are available in Settings. Mac hardware playback continues when the app loses focus.

All 15 audio effect catalog entries now process original synth audio through independently implemented algorithms. Parameter editors include physical units, percentage readouts, bypass, presets and delay/tremolo tempo controls. Imported/AU sources have three serial native FX slots with supported controls only. Audio settings includes output selection and hardware buffer controls.

MIDI editors add Down-Up/Random/Chord arp styles, up to 128 velocity steps, octave Blend, and absolute input/output chord/sequence mappings. Snapshot capture adds FX/MIDI state, pan, modulation and tonic; replacing an effect updates that slot across snapshots. Effect states currently switch at recall; level transitions interpolate.

See the companion [PARITY-STATUS.md](Docs/PARITY-STATUS.md) for verified behavior and remaining gaps. Full 1:1 parity is still unfinished.

## Performance workspace

Fifteen sound positions, five visible strips, setlist/tonic sidebar, Effects/Notes segmented view, snapshots, 88-key piano, colored ranges, dB faders and fixed toolbar follow the inspected Sunday Keys workflow. This is a closer implementation, **not a verified pixel-perfect or feature-complete replica**. Editors, browser, graphic EQ, empty states and some dimensions still differ.

- Channel settings: synth ADSR, voice limit, modulation-wheel filter, eight-band EQ, compressor, gain, pan, sustain blocking, note range, octave transpose and fader bounds.
- Original synths have three serial slots supporting Tone, Tremolo, Delay, Bitcrusher, Chorus, Compressor, Equalizer, Flanger, Gain, Halo Shimmer, Overdrive, Pitch Shifter, PrimaVerb, Rotor and SolaVerb. Algorithms are original approximations, not sonic replicas; some Sunday-specific parameters remain absent.
- MIDI slot: bypass, octave doubling, major/minor/power/octave chords, arpeggiator (up/down/up-down/as-played, 1–4 octaves) and a pitch/velocity/rest sequencer of up to 128 steps. Rate/gate follow patch tempo. These are prototype implementations; they do not reproduce every Sunday Keys MIDI mapping/grid feature, and use main-run-loop timing rather than sample-accurate scheduling.
- Layers opens a full workspace with reverse-order channels, draggable range endpoints and reorder buttons. Reordering also moves snapshot levels and MIDI level assignments.
- Notes mode shortens strips and exposes snapshot-linked notes. The note editor supports five explicit lines and left/center/right alignment.
- Snapshot capture/recall interpolates levels in time or beats. Right-click/long-press to customize, capture, reorder or clear. Newly captured snapshots include FX/MIDI state, pan, modulation and tonic settings alongside levels and notes; old snapshots preserve their existing content.
- Tonic pad is independent from the 15 modules. Brightness and synthesized octave shimmer are original algorithms.

## External sounds and apps

Open a channel header or an empty sound position to use the sound browser:

| Browser section | Support |
|---|---|
| StageKeys | Three original synths |
| Import Sound | SF2/DLS banks, WAV/AIFF/CAF single samples, Apple Sampler AUPRESET plus selected sample folder |
| Audio Units | Installed MIDI instrument AUs on Mac; available AUv3 instruments on iOS/iPadOS |
| External MIDI | System MIDI destinations and StageKeys to External App virtual source |
| Host Patches | Opens MainStage PATCH / Ableton ADG or ALP in its original host on Mac |

Single samples map chromatically with MIDI note 60 as root. Bank program is selectable in channel Settings; bank MSB/LSB currently use descriptor defaults and do not have UI controls. AUPRESET import validates Apple's sampler identity, copies referenced samples from the explicitly selected folder and rewrites file references. It does not import arbitrary AU preset formats. Imported files live in Application Support/StageKeys/Imported Sounds.

Imported instruments have their own native filter/EQ/compressor/pan chain. Envelopes and polyphony belong to the sampler/plugin; three native serial insert slots support Tone, Delay, Compressor, EQ, Gain, Overdrive, Pitch and Apple reverb approximations. Unsupported effects/controls are dimmed or omitted. AU instruments can open their own interface from channel Settings. Plug-in edits take effect live and are saved on closing that interface; Sound Settings' Discard only discards the channel-setting draft.

External MIDI sends notes, note-offs, sustain, CC7 level and CC10 pan. Select **StageKeys to External App** as input in MainStage/Ableton, and assign distinct MIDI channels for separate host instruments. External-app audio stays in that app. This is not an audio-return cable. VST/VST3 hosting is not implemented; use an AU version or a separate VST host with MIDI input.

The free Sunday Sounds MainStage/Ableton packs are host presets, not Sunday Keys App presets. All ten MainStage volumes were downloaded/inspected; none contained standalone sample audio. Ableton Volume 1 contains an ALP Live Pack. See the companion [FREE-PATCHES.md](Docs/FREE-PATCHES.md) report for counts and compatibility. MainStage/Ableton host playback remains unverified end-to-end.

## MIDI, persistence and building

System MIDI sources connect automatically, excluding StageKeys' own virtual output to prevent feedback. Settings supports all/one input channel, recent-message monitor, metronome and performance options. MIDI Learn assigns CC faders to all fifteen sound levels. CC1 is modulation; CC64 sustain; CC120/123 Panic. Program Change selects the zero-based patch position. Patch Lock blocks selection.

Version-4 JSON stores the active setlist. Version-1/2/3 files migrate to fifteen positions, preserving identities, levels and settings. The original active file is backed up before its first v4 save. Global audio/display/MIDI/tonic preferences, last patch/snapshot selection and visual mode save separately in settings.json. Save is atomic. STAGEKEYS_DATA_DIR overrides the development setlist/settings directory. Imported sample assets are not embedded in setlist exports; copy/reimport them on another device. Audio Units must be installed there. Plug-in state is limited to 2 MB per channel; setlist import/export to 64 MB.

Open StageKeys.xcodeproj in Xcode. StageKeysMac targets macOS; StageKeysMobile targets iPhone/iPad. Select your Apple development team to install on a physical mobile device; an installable signed IPA is not supplied. project.yml is the XcodeGen source.

## Verification

- Universal Mac Release and unsigned physical-device iOS/iPadOS Release builds pass.
- Synth and rack tests pass: instruments, release/sustain, transpose identity, fades, 15 sound buses plus tonic, pan, three effects, metronome, panic/overflow and MIDI UMP. Rack/channel DSP tests pass with AddressSanitizer and UndefinedBehaviorSanitizer.
- Channel DSP tests cover envelope, per-channel voice limit, filter/EQ/compression responses and finite output.
- MIDI tests cover routing, chords, arp order, gate, sequence velocity/rest, panic, reconfigure and Codable.
- Model tests cover migration, independent duplication and malformed-state rejection.
- Production performance-store tests cover offline audio, note lifecycle, range/reorder, capture/remove, patch selection/lock, duplication, save and preference/setlist restoration.
- Production AVAudioEngine graph renders the supplied stereo demo WAV.
- Generated WAV import and copied/relinked sampler preset both render audio. Sampler removal, sustain and panic are tested.
- Installed third-party OB-Xd AU passes instantiation, state restore, MIDI and offline rendering. Its native interface was opened in the packaged Mac app. The installed Apple DLS bank also renders through import; additional third-party AUs, SF2 fixtures and AUv3 devices remain unverified.
- Virtual external-app MIDI passes real CoreMIDI send/receive tests. Production input tests cover hot-plug, two sources, unplug cleanup and audible graph output; the real Alesis Prestige connection and audio were confirmed. All 15 effect tests and channel-panic tests pass with sanitizers.
- Mac UI checked: rack, channel tabs, layer editor, sound browser, AU load and native plug-in interface. Phone/tablet runtime layouts, multitouch, hardware MIDI latency and interruptions remain unverified; no simulator runtimes are installed.

## Outstanding work

Exact 15-effect DSP parity and omitted proprietary controls, sample-accurate MIDI scheduling, full snapshot parameter morphing, multisample authoring, cloud/Prime, category hardware-output routing, full MIDI Learn targets and multi-setlist library UI remain outstanding. Ultimate-only workflows could not be inspected in the signed-in Demo license. See [DEEP-UI-AUDIT.md](Docs/DEEP-UI-AUDIT.md) for every accessible effect editor and page examined.

Patch switches currently silence held notes and share module-position DSP rather than maintaining independent old/new audio tails. Shared reverb can retain a brief tail after Panic. The synth is not oversampled; automation can produce coefficient-step artifacts. MIDI inputs now track identical notes independently across devices/channels. The prototype needs device, latency and sustained stage-use testing before live reliance.
