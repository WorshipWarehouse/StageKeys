# Piano fidelity — v0.19

## What the comparison established

The managed SK App Felt Piano instrument preserves the original native Instrument dictionary and all 222 referenced sample hashes. With resident samples, original and managed instrument renders matched with zero relative squared error at note/velocity pairs 48/40, 60/100 and 72/120, including note-off and release. This verifies the sampler instrument, not the whole Sunday Keys channel or patch.

Faster-than-real-time tests previously ran with disk streaming enabled. That can introduce reader gaps despite successful render status. Mac offline tests now disable disk streaming and set the documented offline-render flag. Real-time playback keeps streaming enabled to avoid loading large libraries into memory. Synthetic 220 Hz and 880 Hz samples verify actual source content rather than merely nonzero output.

## Restored voicing

The accessible Sunday Keys demo's **SK Felt Piano | Room** uses substantial channel processing. A new library variant reuses the existing private native instrument and applies the observed sampler level (-3 dB), EQ, 3:1 channel compression with 20 ms attack, 200 ms release, -26 dB threshold, 68% blend and +3 dB output, plus the observed room effect controls. The eight EQ frequencies are 20, 200, 197, 345, 1000, 5417, 1734 and 9000 Hz; corresponding shelf/peak gains are -3, -2, -5.5, 0, -6 and +7.5 dB. Peak bandwidths are converted from the displayed octave values to stored Q.

The library variant appears only when the user's native Felt Piano instrument is already installed. No Sunday-owned audio is bundled. Sound Settings also offers **Use Felt Piano | Room Voicing**, with normal live preview, Discard and Confirm. The compressor now has Input, Envelope, Loudness, Mix and Output columns; input gain, ratio, dry/wet and output gain work for imported instruments as well as the built-in synth.

Touchstone's source Live preset contains a saved clean low-pass cutoff around 2754 Hz, amplitude velocity depth 0.1953125, and a modern Delay device that earlier translations omitted. The converter now retains supported clean low-pass cutoffs, scales the native attenuation connection by the saved amplitude velocity depth, and translates modern Delay timing/link/sync, filter, feedback and mix. It disables the unrelated CC1 pitch-vibrato route inherited from Apple's generic sample template. Original sample zones and audio bytes remain unchanged.

The backed-up rebuild was verified on all 213 free imports in an isolated library, followed by production playback across all ten volumes and every parallel instrument patch. ApplyFactoryVoicing was checked against a copied Piano Patch: only pristine native Felt Piano channel voicing changed; other patches, gains and routing were preserved.

## Remaining differences

Room reverb is StageKeys DSP, not a verified equivalent of Sunday's algorithm. Its 9% predelay display is currently approximated as 18 ms. EQ values were read from rounded UI displays, shelf shapes may differ, and the compressor model has not been null-tested against Sunday's. Live filter slope/circuit, velocity-filter modulation, envelopes/LFOs and attenuation curves remain incomplete. Modern Delay's saved sixteenth chooser ordering is inferred. These changes improve reconstruction but do not establish identical Live or Sunday patch audio.

The native sampler did not honor an attempted saved voice-count change in verification. Imported voice count therefore remains disabled rather than exposing a control with no verified effect. Physical iPhone/iPad listening and the final native UI inspection still require device verification.
