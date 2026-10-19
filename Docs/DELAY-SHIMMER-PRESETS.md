# Delay, Shimmer and preset coverage — 0.43

## Shimmer processing

The former octave shifter read the same raw-input ring as the simple reverb taps. At high Amount, its short pitched attack replaced most of the diffuse return. Halo Shimmer now uses four independently delayed room paths and two delayed all-pass diffusion stages before an octave shifter with its own wet-only history. Pitch feedback returns to the room through a bounded blend, rather than repeatedly shifting the direct input. Room size controls the room decay; Diffusion controls the all-pass stages, Modulation varies the room lines, and the stereo processor decorrelates left/right delays. Quality still changes only the wet processing clock. Crossfaded grains produce audible pitch sidebands; transparent harmonic shifting and exact source tone remain unverified. Dry/Wet levels remain independent.

Generated audio verifies energy in the octave-up band, unshifted content with Amount zero, delayed wet onset, continuous tail energy, stereo decorrelation, bounded maximum feedback, unchanged dry output and complete panic reset. The shared processor covers performance slots, imported rack instances and Tonic's shimmer path. Original samples and saved parameter arrays are unchanged. This is an independent native algorithm, not verified Sunday DSP equivalence; listening verification remains necessary.

## Delay controls and Default

A fresh installed-app inspection confirms a Settings section with Feedback slider, five subdivision choices and Ping-Pong mode, plus separate vertical Filter and Mix controls under Output. The reference Default menu exposes only Default in the current session. Applying it sets Feedback 30%, dotted eighth subdivision, Ping-Pong on, Filter 1000 Hz and Mix 50%. Halo's and SolaVerb's menus likewise expose only Default in the inspected session; its observed Amount 75%, feedback 66%, size 90%, diffusion 75%, modulation 50%, quality 100%, low cut 100 Hz, Dry 100% and Wet 20% match the retained native defaults. Sunday's Tone percentage taper remains unmeasured.

StageKeys' Delay panel follows that organization. Selecting a new Delay or applying Default supplies the observed dotted-eighth/ping-pong settings; old saved delays keep their own subdivision and mode. An optional `delayPingPong` field survives preset saves and previews. The imported-instrument performance effect now passes its resolved stereo delay descriptor to the native stereo processor. This fixes a missing adapter between the editor and the audio unit. Existing imported stereo-channel routing remains separate. The built-in synth is mono before its final pan, so Ping-Pong is disabled there rather than presented as a working stereo control. Extreme low-tempo/long-delay capacity still requires broader verification.

Preset selection remains Select → Apply → Confirm; Discard restores the original patch, and personal effect presets remain available. Reference-app edits during this inspection were discarded.

## Complete archive inventory, incomplete native conversion

`Tools/audit-mainstage-presets.py` recursively inspects top-level .patch packages, skips nested template patches, hashes each channel document and matches exact native library channel IDs. Missing/unreadable/unsafe channels and unsupported patch lists remain explicit. No MainStage process, source plug-in or MIDI script is launched.

The private Sunday Free archive contains **358 patches and 427 channels**. Nine channel occurrences have native entries, across two patches with full channel coverage; one patch lacks a supported channel list. Full channel coverage does not establish complete patch routing/effect fidelity. The remaining archive entries are preserved source presets, not native playable conversions. In particular, ES2/Retro Synth/Sculpture instruments need their own engine translations; a sampler cannot replace them. This audit prevents reporting an archived preset as successfully converted. It does not bundle or copy vendor sounds into the application repo.

## Steinway level investigation

The prior fixed-velocity reference was reused without changing MainStage or requiring more keyboard downtime. A temporary candidate replaced only the amplitude attenuation law with a linear half-depth route, while retaining the source filter, sample map, unity controllers and reference channel EQ. The independently measured host-curve gain was applied in analysis. Relative level differences across pitches 60/74/86 and velocities 38/64/83/102 narrowed, but the candidate stayed 2.84–5.02 dB below the reference. It was **not applied** to the installed library or shipped as a blanket gain adjustment. Sample-layer transitions, exact filter/EQ response and front-panel level interpretation still need controlled calibration. Existing host-curve, click, loop and latency fixes remain unchanged.

## Release verification

Universal Apple Silicon/Intel macOS and iPhone/iPad simulator Release builds passed. The sanitizer reverb suite, Shimmer quality and octave-band/tail tests, stereo delay timing/cross-feedback tests, native effect AU tests and effect-preset persistence checks passed. The private pack's nine native channels retained their settings and produced finite audio at all 36 tested note/velocity points. The preset inventory fixture verifies exact channel hashes, nested-package skipping and explicit missing-channel reporting. The sample-free app distribution audit passed.

Native Mac inspection verified the new Delay Default, dotted-eighth selection, Ping-Pong on/off, subdivision edits and Filter adjustment. Discard returned to the user's bypassed Halo slot, and the saved setlist remained semantically identical to the pre-update copy. StageKeys 0.43/build 47 opened successfully. Physical iPhone/iPad listening and exact Sunday effect equivalence remain unverified.
