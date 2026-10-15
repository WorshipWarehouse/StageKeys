# Piano fidelity — v0.22

## Identified reverb core

Read-only Swift field metadata in the installed Sunday Keys app identifies `Audio.PrimaVerb` with `Audio.AirwindowsCreamCoat`, `Audio.HighPassLowPassEqualizer`, chorus and `Audio.AppleDryWetDualMixer` state. CreamCoat's wrapper fields are selection, regen, derez, predelay and wetness. This establishes the processor family, not its exact revision, parameter transforms or graph order. No proprietary implementation code or sound assets were copied into StageKeys.

StageKeys adapts the [official Airwindows CreamCoat double processor](https://github.com/airwindows/airwindows/blob/7623a1c14b012a1a6407bb0e3ba252d1f027a823/plugins/WinVST/CreamCoat/CreamCoatProc.cpp) under its [MIT license](../Licenses/Airwindows-MIT.txt). Delay tables, stereo feedback matrix, Bezier reconstruction, regeneration equation and quantized DeRez behavior are retained. Host changes are standalone C state, deterministic denormal-noise seeds, cached block preparation and float I/O. It uses the upstream double path without adding float dither. Core memory is allocated on the control thread, retained through bypass, and reset by panic; rendering performs no allocation.

A local independent build of the unmodified upstream double processing routine was compared to the adaptation over 4,896,000 stereo frames: all 17 selections, 44.1/48/96 kHz and Quality 100/55/10%, with reflectivity 33% and predelay 9%. Maximum float-output difference was zero. Repository impulse goldens cover zero and 9% predelay, with sanitizer checks for stereo wiring, dry identity, panic and bypass reset. Run `Tests/test-reverb.sh` on macOS for the checked-in DSP regressions. This verifies the adaptation against upstream, **not a null test against Sunday Keys**.

The source-family path maps serialized predelay `p[1]/200` to normalized CreamCoat D, Quality to DeRez C, reflectivity to B, and normalized size to A; the core is wet-only and the host adds independent dry/wet levels. These wrapper mappings are informed by the matching field names but remain inferred. In particular, the seven UI sizes currently span the upstream 17 selections; Sunday's exact table is unverified. At 48 kHz/full quality/Small Room, a 0.1 impulse crosses 1e-6 at frame 517 without predelay and frame 3215 at 9%. The resulting 2698-frame onset difference is about 56.2 ms, not the old assumed 18 ms. Internal undersampling/rounding makes this different from a simple delay in milliseconds.

The observed unchanged Felt Room profile automatically selects the core without rewriting its saved parameters, gains, routing or other channels. New PrimaVerb selections and freshly reconstructed Felt Room sounds use it explicitly. An optional `reverbCore` field retains that choice through editor confirmation and saved presets. Other existing imported reverbs keep their legacy engine and literal millisecond predelay. Legacy nine-parameter effects still supply full Quality without rewriting their arrays. Wet-path EQ and nonzero chorus remain StageKeys approximations; the Piano profile's chorus amount is zero.

## Preset interaction

Sunday Keys' accessible PrimaVerb menu was inspected: selecting Default reveals Apply; Apply loads Medium Hall, 0% predelay, 30% reflectivity, 100 Hz low cut, 20 kHz tone, Quality 100%, chorus 0%/1 Hz, Dry 80% and Wet 40%. Source changes were discarded. StageKeys now follows selection → Apply and offers Save Preset as, with named presets stored atomically in the personal `effect-presets.json`. Applying presets previews the draft, retains the current power state, and respects the editor's Discard/Confirm boundary. Canceling preset naming writes nothing. Preset archive tests cover round-trip settings/core identity, invalid-save preservation and malformed-data rejection.

The native Audio Unit also matches the direct stereo core with zero relative error and the same frame-3215 onset; this catches engine-selector loss at the Swift/C boundary. Universal Apple Silicon/Intel Mac and iPhone/iPad simulator Release builds pass. Live tests preserve all 222 Felt and nine Touchstone sample references across graph edits, and their waveforms remain distinct. Synthetic live hot-swap tests verify original fundamentals and upper harmonics; parallel graph and groove regressions also pass. Native Mac inspection verified preset selection leaves controls unchanged, Apply matches source defaults, naming Cancel, and editor Discard. Physical iOS listening and complete source-output parity remain outstanding.

The following sections document the earlier v0.20/v0.21 implementation and its evidence.

## Fixed live sampler regression

Rebuilding the imported effect graph reinitialized AUSampler, cleared its sample references and left its default sine tone active even though AVAudioEngine.start succeeded. Direct sampler comparisons did not exercise this later graph rebuild, and the older production checks accepted any finite audible output.

Graph edits and instrument installation now snapshot each sampler's fullStateForDocument, including file references, and reload it after connections are rebuilt, before rendering restarts. Newly created parallel-branch samplers are included. Default full-keyboard zone ranges are written explicitly: AUSampler omits them in saved state, which otherwise lets filename inference narrow zones during reload. Plain-audio mapping also uses document state so sample references survive mapping edits. Only owned sampler nodes are enumerated, avoiding input-node creation and unintended microphone access. The Mac process raises its own file-descriptor soft limit within the existing hard limit; GUI apps otherwise start with a 256-file budget, which can exhaust while reloading a streamed multi-sample piano. Both piano fixtures pass with the test launched under that 256-file limit.

A live production regression loads 220 Hz and 880 Hz samples with a third harmonic through Store MIDI and switches back again. Before the fix, the output was dominated by the default C sine and references were empty. After the fix, the referenced fundamental and upper harmonic survive each switch. A personal-fixture test loads Felt Room and Touchstone together, rebuilds effects, verifies all 222/9 references remain, and checks that their live output differs. It uses an isolated setlist and does not change the user's patches.

Reverb predelay now delays the input entering the tank using a separate preallocated buffer. The previous implementation mixed a feedback-tank tap into the wet signal. Impulse tests verify an exact 18 ms wet shift with modulation off, unchanged dry attack, and complete panic cleanup. This corrects predelay behavior; it does not establish equivalence to Sunday's room algorithm.

The compressor editor uses compact knobs so all five columns fit the sound editor without hiding release and threshold. Narrow displays retain scrolling. The Mac release was opened normally and inspected with its AudioBox USB 96 output running at 48 kHz/512 frames; all compressor controls and saved values fit the panel.

## PrimaVerb controls and stereo tail

The accessible Felt Room effect was inspected again in Sunday Keys. Its size stepper has seven choices: Small Room, Medium Room, Large Room, Medium Hall, Large Hall, Ambient Hall, and Cathedral. The editor groups Settings, Character, Modulation and Output, with Quality at 100%, Chorus AMT at 0%, Chorus Rate at 0 Hz, Dry at 100% and Wet at 23%. Inspection changes were discarded in the source app.

StageKeys now has this grouped layout, named size stepper, percentage predelay, inline knobs, output faders, power button and right-aligned Discard/Confirm actions. The percentage view retains the existing 0–200 ms predelay scale: 9% still means 18 ms here. That scaling has not been verified against Sunday's DSP. Seven UI size positions map to the existing normalized size range; old continuous values remain unchanged until edited.

PrimaVerb now accepts 0 Hz chorus rate. Quality is an appended control: nine-value presets still validate and preserve their serialized values, while playback and editing supply 100% Quality when it is absent. StageKeys uses Quality to interpolate wet tap density; this is an independent implementation, not a verified model of Sunday's Quality algorithm. The new factory Felt Room profile stores the observed zero rate and full quality. Existing user effects keep their stored settings.

The right reverb tank uses different delay lengths so mono sources no longer produce identical left/right wet tails. The dry signal and its timing remain unchanged. Impulse tests check stereo decorrelation, bounded energy, quality behavior, dry passthrough, predelay and panic cleanup. Live real-piano tests and waveform/harmonic tests continue to check that effect edits do not replace sampler instruments with fallback tones. The Mac editor was inspected with the user’s existing Piano Patch: size bounds, power and Quality edits worked, and Discard left the saved setlist, settings and library semantically identical to their backups.

## What the comparison established

The managed SK App Felt Piano instrument preserves the original native Instrument dictionary and all 222 referenced sample hashes. With resident samples, original and managed instrument renders matched with zero relative squared error at note/velocity pairs 48/40, 60/100 and 72/120, including note-off and release. This verifies the sampler instrument, not the whole Sunday Keys channel or patch.

Faster-than-real-time tests previously ran with disk streaming enabled. That can introduce reader gaps despite successful render status. Mac offline tests now disable disk streaming and set the documented offline-render flag. Real-time playback keeps streaming enabled to avoid loading large libraries into memory. Synthetic 220 Hz and 880 Hz samples verify actual source content rather than merely nonzero output.

## Restored voicing

The accessible Sunday Keys demo's **SK Felt Piano | Room** uses substantial channel processing. A new library variant reuses the existing private native instrument and applies the observed sampler level (-3 dB), EQ, 3:1 channel compression with 20 ms attack, 200 ms release, -26 dB threshold, 68% blend and +3 dB output, plus the observed room effect controls. The eight EQ frequencies are 20, 200, 197, 345, 1000, 5417, 1734 and 9000 Hz; corresponding shelf/peak gains are -3, -2, -5.5, 0, -6 and +7.5 dB. Peak bandwidths are converted from the displayed octave values to stored Q.

The library variant appears only when the user's native Felt Piano instrument is already installed. No Sunday-owned audio is bundled. Sound Settings also offers **Use Felt Piano | Room Voicing**, with normal live preview, Discard and Confirm. The compressor now has Input, Envelope, Loudness, Mix and Output columns; input gain, ratio, dry/wet and output gain work for imported instruments as well as the built-in synth.

Touchstone's source Live preset contains a saved clean low-pass cutoff around 2754 Hz, amplitude velocity depth 0.1953125, and a modern Delay device that earlier translations omitted. The converter now retains supported clean low-pass cutoffs, scales the native attenuation connection by the saved amplitude velocity depth, and translates modern Delay timing/link/sync, filter, feedback and mix. It disables the unrelated CC1 pitch-vibrato route inherited from Apple's generic sample template. Original sample zones and audio bytes remain unchanged.

The backed-up rebuild was verified on all 213 free imports in an isolated library, followed by production playback across all ten volumes and every parallel instrument patch. ApplyFactoryVoicing was checked against a copied Piano Patch: only pristine native Felt Piano channel voicing changed; other patches, gains and routing were preserved.

## Remaining differences

The legacy imported-room path remains StageKeys DSP. The Felt Room path now uses the identified CreamCoat family, but the complete Sunday wrapper, room-selection table, EQ and chorus are not verified equivalent. EQ values were read from rounded UI displays, shelf shapes may differ, and the compressor model has not been null-tested against Sunday's. Live filter slope/circuit, velocity-filter modulation, envelopes/LFOs and attenuation curves remain incomplete. Modern Delay's saved sixteenth chooser ordering is inferred. These changes improve reconstruction but do not establish identical Live or Sunday patch audio.

The native sampler did not honor an attempted saved voice-count change in verification. Imported voice count therefore remains disabled rather than exposing a control with no verified effect. The installed Mac library and Piano Patch were upgraded with backups; native UI inspection verified the Room EQ and compressor values. Compressor panels now scroll vertically so release and threshold remain reachable. Physical iPhone/iPad listening still requires device verification.
