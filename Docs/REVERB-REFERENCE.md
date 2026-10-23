# Sunday Sounds reverb behavior reference

Source: https://sundaysounds.com/blogs/news/new-reverbs-added-huge-sunday-keys-update (27 May 2026; reviewed 19 October 2026).

The article describes PrimaVerb as acoustic room/hall models, with distinct tonal characters for the size selections. SolaVerb is an ambient modulated reverb. Both place chorus before the tank; SolaVerb additionally varies individual internal delay lines. Quality reduces sample rate and is a setup control, not a performance control. Size likewise should be selected before playing. Separate dry and wet levels support wet-only pad textures.

## Implemented correction

PrimaVerb's source-core path formerly chorused its finished wet output. Chorus now processes the input to the tank, in both the built-in mono path and imported stereo effect path. Dry audio bypasses that processing. Existing zero-chorus presets retain their response. The chorus history is preallocated and cleared by Panic, as before.

`ReverbChorusPlacementTests` excites the tank, waits a second for the input history to clear, then enables chorus. The already-running tail must remain unchanged. It checks both render paths; a post-tank implementation fails this invariant. The full sanitizer reverb suite also covers impulse responses, predelay, stereo, Shimmer aliasing and stable tails.

## Remaining differences

This article is a behavioral specification, not source DSP or proof of sonic equivalence. StageKeys SolaVerb still uses an approximate tank; 0.50 adds an independent wet-clock Quality parameter, with its exact source taper unverified. Version 0.45 moves pitch modulation to individual delay lines and separates the pre-tank chorus. Its diffusion, tonal response and modulation ranges still need matched listening. PrimaVerb's room models, reflectivity envelope, modulation ranges and Quality taper need matched listening/measurement. Halo Shimmer is a separate effect; the article does not specify its octave-shifting algorithm. Do not use it as evidence that Shimmer matches.

Steinway loudness/velocity calibration remains open; this chorus fix does not change sampler gain or velocity mapping. Remaining source patches requiring unavailable instruments or native synth engines remain blocked rather than receiving substitute sounds.

## Isolated reference measurement

The 19 October piano-only capture validates 12 isolated notes with peak 0.4822 (48 kHz), excluding a first take contaminated by a mapped CC11 message that raised MainStage's pad fader. The accepted sequence omits CC7/CC11. MainStage piano/output faders were temporarily −0.2 dB each, then restored to −∞ alongside the pad; recording is off. See `Calibrations/Steinway-Piano-Only-v49.json`. Against the saved native baseline, the soft/hard difference changes sign with velocity. This supports further amplitude-law calibration, not a blanket output boost. Channel/output EQ still needs isolation. Original samples and the running user's patch remain untouched.

## SolaVerb 0.45

Replaced the shared feedback tank/output pitch blend with four independently modulated feedback paths, two diffusion stages, and a separate pre-tank chorus. Reflectivity now sets a continuous decay target rather than multiplying one short shared loop. Predelay affects only wet excitation. The UI separates Character from Modulation. Existing parameter indices and saved presets remain valid; their wet sound changes with the new algorithm. Quality was subsequently added in 0.50; see CONVERSION-AND-LEVEL-MATCH-v50.md.

Sanitizer tests cover independent pitch/chorus behavior, dry identity, sustained finite tails and Panic at 44.1/48/96 kHz. The full reverb suite retains Shimmer octave/tail/alias regressions. This is independent DSP, not measured Sunday Keys sonic parity.

## SilverVerb 0.51

Late-tank feedback now includes frequency-dependent damping. See [the measured improvement and wideband-envelope tradeoff](REFERENCE-MATCHING-v51.md). This change does not revise Shimmer or establish full reverb equivalence.

## Versioned Dense engines 0.53

New acoustic and ambient effects now default to an independent coupled feedback network. Legacy and CreamCoat engines remain selectable through existing saved patches. See [DSP audit, controls, tests and remaining acceptance work](REVERB-ENGINES-v53.md). Full reference listening parity and physical-device qualification remain unverified.
