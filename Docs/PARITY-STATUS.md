## 0.7 update

Observed Sunday Keys channel editor: three main tabs, eight EQ knob columns (not a graph), two-column settings, and channel transpose explicitly before MIDI effects. Implemented corresponding UI structure, pre-MIDI-FX channel transpose, full sound presets in My Sounds, local setlist create/switch/rename/duplicate/Trash/restore, and layer drag/drop with identity-preserving reorder. Mac and mobile release builds pass; hardware MIDI/audio regressions and library/reorder/routing tests pass. Native Mac UI verified the eight-column editor, staged edit/discard, local setlist create/switch/Trash, and actual sound-order changes using the draggable grip. The temporary test setlist was archived and Sunday Morning restored. Full parity and remaining 0.6 sound-conversion gaps are not claimed complete.

## 0.6 update

Native Sunday app sampler import verified for 21 downloaded instruments; Sunday Free volumes remain MainStage host entries. Sampler library folder import and sample-containing export/relink are implemented. Modulation is now a wheel with hosted/external MIDI CC1 routing. Snapshot modulation, tonic gain and brightness fade; device selection persists by UID. Full UI/DSP parity, free-volume capture and native mobile runtime tests remain incomplete. Cloud/Prime excluded.

## 0.5 update — local workflow scope

Cloud/Prime excluded by user request. Persistent reusable sound library and EXS24 import added; snapshot compatible effect/pan interpolation wired into live recall. Sunday Free library installed privately on this Mac: 358 MainStage patch bundles across volumes 1–10. Host entries require MainStage; full native preset-chain conversion remains pending. EXS base-instrument import succeeds on several installed legacy orchestral instruments, but does not reproduce free CST effect chains. Visual parity remains incomplete.

# StageKeys 0.4 parity status

This is ongoing work toward the requested Sunday Keys UI/functionality match. It is **not complete 1:1 parity**. The signed-in Sunday Keys 2.5.2 Mac app remains in Demo Mode, so Ultimate/Prime-only flows cannot be verified. The original code, artwork and sample library are not reused.

## MIDI plug-and-play: fixed and verified

The Alesis Prestige initially existed only as an offline CoreMIDI device and was absent from the live USB inventory. After reconnection it appeared as a live source. The updated app displayed **Alesis Prestige — Connected**, received actual Channel 1 note-on, velocity-zero note release and CC64 sustain messages, and the user confirmed audio worked.

The prior input client disconnected/reconnected all sources and called Panic for every device notification. The new client diffs connections, debounces notifications, polls for missed hot-plug events and does not disturb stable inputs. Start is idempotent. Source/channel note identity prevents one keyboard releasing another keyboard's note. Unplugging clears only that input's held notes and pedal. Mac focus changes release on-screen touches while keeping hardware playback active. Audio route changes attempt automatic recovery.

Settings now shows named connected/offline devices, Primary/Secondary source/channel choices, velocity limits, refresh and Plug and Play Defaults. USB controllers accepted by macOS connect automatically. Bluetooth/network devices are assigned after connecting them through Audio MIDI Setup on Mac.

Automated tests verify CoreMIDI hot-plug after launch → production PerformanceStore → audible AVAudioEngine output, two sources playing the same pitch, stable refresh, note-offs, sustain/unplug, and survival of the remaining input. This is separate from the real Prestige confirmation.

## UI and functional progress

| Surface | Current implementation | Remaining differences |
|---|---|---|
| Performance rack | Refined measured header/sidebar/strip geometry, shaded caps, custom master fader, 15 slots, colored ranges, Notes layout | Exact icon artwork, every spacing/detail and device-size runtime comparison |
| Audio FX | All 15 catalog entries have real DSP for original synths; physical parameter editors, bypass, tempo-related delay/tremolo | Independent approximate algorithms; omitted Sunday-specific quality, ping-pong and cabinet/mic options; not sonic parity |
| Imported/AU FX | Three serial native slots with wet/dry, tested gain summation, live replacement | Only Tone/Delay/Comp/EQ/Gain/Overdrive/Pitch/native verbs; other types dimmed; unsupported controls omitted |
| MIDI FX | Four types, octave blend, arp styles/velocity grids up to 128, absolute input/output chord/sequence mappings, rests/velocity, per-source release | Main-run-loop clock rather than sample-accurate scheduling; exact original mapping gestures/layout still differ |
| Snapshots | Capture/recall levels, FX state/parameters, MIDI state, pan, modulation, tonic settings; effect replacement updates existing snapshots | Level fades interpolate; effect/tonic/mod state currently switches at recall rather than full parameter morphing |
| Sound settings | ADSR, voice count, filter, eight-band EQ, compressor, semitone transpose, pan, sustain/ranges/fader bounds | EQ graph/column layout still differs; imported instruments own envelope/polyphony; exact sound-type tab rules not reproduced |
| Layers | Full overlay, reverse-order rows, named notes, aligned draggable endpoints and working reorder menu | Drag-based reordering and exact help/interaction details |
| Audio settings | Output device selection, sample rate/buffer status, hardware buffer control, rollback/restart handling | Device selection/buffer UI compiled and read-only/invalid-operation tests pass; valid hardware mutations not runtime-tested |
| Libraries | Original synths, user sample/bank/preset import, AU state/editor, external MIDI/host patches | Full sound catalogue/library manager, multiple setlist library UI, downloaded Sunday library compatibility |
| Cloud/Prime/account | Inspected accessible pages and restrictions | Independent backend/workflows not implemented; license-hidden behavior unverified |

## Validation

Universal Mac and unsigned iOS/iPadOS release builds pass. Synth/rack/channel/effect tests pass with AddressSanitizer and UndefinedBehaviorSanitizer. Each effect produces finite audio and audible processing, bypass restores dry sound, panic clears tails, and pitch shift has a spectral check. Channel panic preserves other sustained channels. MIDI/model/production-store tests pass, including v1–v3 migration to v4 and effect/modulation snapshot recall. Imported WAV/preset, installed Apple DLS, serial native FX and installed OB-Xd AU tests pass. Original installer/sample assets are excluded from the distributable.

Physical iPhone/iPad UI, hardware MIDI latency, all third-party plugins, exact DSP comparison and sustained stage-use testing remain outstanding.
