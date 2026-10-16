# MainStage effects, Tonic Pad and optional libraries — 0.29

The MainStage processing preview now supports the observed Stereo Delay, SilverVerb and ClipDist parameter records. This is active native processing, not a claim of identical proprietary DSP. Original channel strips remain archived, and processor bypass flags still need independent decoding. Applying processing remains a reviewed editor draft; existing effects, levels and sample maps are preserved.

## Stereo Delay

Apple's local `Stereo Delay/CSParameterOrder.plist` identifies parameter 10 as Beat Sync, 11/13 as the left/right note denominators, 12/14 as percentage deviation, 15/16 as input routing, and 17–20 as signed feedback/crossfeed polarity. v0.28 incorrectly treated parameter 15 as a right sync flag. Synced duration is `4 / noteDenominator * (1 + deviation / 100)` quarter-note beats, and the current patch tempo converts beats to seconds. Factory preset pairs corroborate the percentage deviation: e.g. eighth note at −34% and half note at −34% produce proportional 220/880 ms saved times.

Crossfeed 6 routes L→R; 7 routes R→L. Each channel retains separate feedback, crossfeed, mix, filters, input selection and polarity. Input choices are Off, Left, Right, L+R and L−R; native sum/difference is normalized by one-half. The advanced imported controls expose those settings. Feedback magnitude sums are limited to 0.95 for bounded processing. Tempo-freeze is explicitly unsupported. Delay changes are immediate; original interpolation, routing gain law and filter response are not verified identical.

See [Apple Stereo Delay](https://support.apple.com/en-asia/guide/logicpro/lgcef18b892f/10.7/mac/11.0).

## SilverVerb and ClipDist

The local SilverVerb parameter-order metadata identifies Mix, Predelay, Reflectivity, Room Size, Density/Time, low/high cuts and modulation rate/intensity/phase. Their saved values drive a separate native four-comb/diffusion network. Predelay alignment, density-dependent tail energy, finite output and panic silence have generated-audio regressions. The native decay curve/comb topology is independent. Extended source Dry/Wet mode remains unmapped; legacy Mix controls the native dry/wet balance. Supported linear macros, including complementary dry/wet mix bindings, remain active.

ClipDist controls drive, highpass Tone, asymmetric nonlinear clipping, Clip Filter, dry/wet Mix, Sum Low Pass, high shelf and input/output gain. The native order follows the documented filter topology with an independent asymmetric soft-clipping curve. It does not reproduce Apple's exact spectrum or oversampling. Source units are retained in the imported control UI. Both new processors are available in imported racks; the observed Sunday Keys performance-effect picker keeps its existing list.

See [Apple SilverVerb](https://help.apple.com/logicpro/mac/9.1.6/en/logicpro/effects/chapter_11_section_6.html) and [Apple Clip Distortion](https://help.apple.com/logicpro/mac/9.1.6/en/logicpro/effects/chapter_3_section_2.html).

## Tonic Pad

The pad now has a remembered key, separate power behavior, live rotary Brightness/Shimmer/Volume, snapshot lock, imported instrument selection and persisted timbre. Re-selecting the active key keeps it playing. Brightness filters the signal. Shimmer uses the native pitch-shifted feedback reverb rather than re-triggering an extra octave note. The underlying pad stays held when shimmer changes.

A separately imported v1 tonic sampler is recognized from its verified twelve velocity-selected zones (keys 36–47, exact selector velocities 1–12). Its original Warm/Bright/Dark/Choir/Organ/Guitar/Strings/Pure/Evolving/Rev Piano/Simple/Classic timbres can play through the reserved tonic channel. Other imported pad instruments use ordinary velocity. Tonic-only instruments are browsed in Tonic Settings rather than the normal keyboard library, where the selector format would otherwise be silent at normal playing velocities. The built-in warm synth remains available without any sampled library.

Sunday Keys currently reports Demo Mode and blocks its tonic settings selector. The visible pad controls and previously verified v1 map inform this implementation; exact settings-modal/shimmer/crossfade parity and v2 tonic mapping remain unverified. Tests cover the library-free pad, repeated key selection, power memory, settings persistence and production routing of private v1 fixtures. Physical iPad runtime still requires device testing.

## Application/library separation

[StageKeys-Library](https://github.com/WorshipWarehouse/StageKeys-Library) is a separate private Git LFS repository containing installed sounds and original sound sources. It excludes personal setlists, session settings, ratings, backups and `pluginState` fields. Managed sampler references are portable; original audio/EXS/source patch bytes remain unchanged. Source presets retain authored instrument/effect settings needed to reproduce the sound; personal hosted-plugin snapshots are excluded.

The application has no submodule, build step or runtime network dependency on that repository. Import Sounds → Install a Separate Sound Library validates a selected pack's hashes, confines paths to its root, relocates and copies original samples, retains rack/MIDI/tag/level data and skips existing IDs. It never replaces the active setlist. Archived nonplayable MainStage entries stay in the backup and can be restored with its tool; the app installer adds playable sampler entries. The backup's restore tool writes only into an empty destination.

`Tools/check-distribution.py` rejects sampled assets in tracked app files or a built app bundle. The distribution workflow builds the app with no library checkout and checks the resulting bundle. The separate private backup is not a license to redistribute vendor sounds with a shipped product.

## Release validation

v0.29 passed all twelve library/import regression suites, native effect and stereo-delay audio regressions, and targeted final pad-selection preservation checks. Private fixtures exercised all twelve original tonic timbres and the Two Pianos processing chain. Release builds succeeded for universal macOS and the iOS simulator. The signed macOS release opened with the existing Testing patch, Steinway/SolaVerb, levels and imported Warm tonic selection preserved. Physical iPad playback and listening comparisons against Apple's proprietary processors remain outstanding.

The separate private backup contains 596 catalog entries and 4,390 hash-verified files. A fresh remote clone retrieved a sampler preset through Git LFS and verified its manifest hash. The app source and packaged bundle passed the no-sampled-assets distribution audit.
