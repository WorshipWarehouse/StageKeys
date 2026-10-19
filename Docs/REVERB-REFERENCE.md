# Sunday Sounds reverb behavior reference

Source: https://sundaysounds.com/blogs/news/new-reverbs-added-huge-sunday-keys-update (27 May 2026; reviewed 19 October 2026).

The article describes PrimaVerb as acoustic room/hall models, with distinct tonal characters for the size selections. SolaVerb is an ambient modulated reverb. Both place chorus before the tank; SolaVerb additionally varies individual internal delay lines. Quality reduces sample rate and is a setup control, not a performance control. Size likewise should be selected before playing. Separate dry and wet levels support wet-only pad textures.

## Implemented correction

PrimaVerb's source-core path formerly chorused its finished wet output. Chorus now processes the input to the tank, in both the built-in mono path and imported stereo effect path. Dry audio bypasses that processing. Existing zero-chorus presets retain their response. The chorus history is preallocated and cleared by Panic, as before.

`ReverbChorusPlacementTests` excites the tank, waits a second for the input history to clear, then enables chorus. The already-running tail must remain unchanged. It checks both render paths; a post-tank implementation fails this invariant. The full sanitizer reverb suite also covers impulse responses, predelay, stereo, Shimmer aliasing and stable tails.

## Remaining differences

This article is a behavioral specification, not source DSP or proof of sonic equivalence. StageKeys SolaVerb still uses an approximate tank and lacks an independent Quality parameter. Its pitch modulation must be moved to individual delay lines and its chorus separated from that modulation. PrimaVerb's room models, reflectivity envelope, modulation ranges and Quality taper need matched listening/measurement. Halo Shimmer is a separate effect; the article does not specify its octave-shifting algorithm. Do not use it as evidence that Shimmer matches.

Steinway loudness/velocity calibration remains open; this chorus fix does not change sampler gain or velocity mapping. Remaining source patches requiring unavailable instruments or native synth engines remain blocked rather than receiving substitute sounds.
