# Native EXS synthesis translation

Version 0.34 adds source-wide synthesis controls to the independent EXS converter. It applies to supported newly imported instruments, including instruments found through MainStage patch import; there are no Steinway-name checks. Apple-compatible EXS files that load directly continue using Apple's native importer. Modern files that require StageKeys' map translator now receive the supported synthesis controls too.

## Active playback

* Source master level and global fine/coarse tuning are added to zone gain and cents. Nonzero instrument transpose currently contributes a pitch offset; changing source-zone selection with that MIDI transpose is not yet reproduced. Existing zone gain and tuning remain relative; audio files are unchanged.
* The supported modern low-pass family (type 0, observed as LP 12dB Lush) and legacy type 2 use the native sampler's 12 dB low-pass. Unsupported circuits, drive and second-filter configurations are reported rather than silently called equivalent.
* Global cutoff/resonance and signed group cutoff/resonance offsets are retained. Cutoff uses a 20 Hz–20 kHz logarithmic approximation; resonance uses the native filter's dB control. This is **not an exact reproduction of MainStage's Lush circuit or source control taper**.
* Supported direct velocity, key and MIDI CC routes feed the native filter independently for each voice. Keys track around MIDI 60. Inversion and source bypass are respected. Cached filter/level CCs and the held sustain pedal are reapplied after instrument graph reloads. Unsupported destinations and via combinations are reported. The two saved amount endpoints are not a generic implementation of arbitrary via modulation.
* The two source amplitude attack endpoints become a per-voice linear attack factor. The source group envelope offsets and decay/sustain/release stay in the native envelope. Explicit Attack Smoothing overrides that generated velocity factor; the automatic minimum remains zero.

Mac converted-instrument resident playback is retained. This change adds no scheduling queue, lookahead, sample rendering or resampling. Source amplitude velocity curves, asymmetric pitch bends, exact envelope shapes, other filter slopes/drive/dual filters, advanced modulation and host channel-strip overrides still need translation. New source notes identify these limits.

## Existing library

Import Sounds → **Update Converted Sampler Playback** updates generated v1/v2 EXS instruments with a retained, digest-checked original EXS. It backs up presets plus library/setlist metadata. It preserves sample references, sample/loop/key/velocity bounds, rack effects, names, channel levels and settings. Edited filters are refused; edited envelopes retain their settings and skip the velocity attack update. A failed multi-step update restores the pre-update preset. A version-3 marker prevents applying gain/tuning twice.

The installed Steinway Piano 2 and legacy Steinway Grand Piano 2 are different source presets. The latter's 6 dB filter is still reported as unsupported; it is not substituted with a 12 dB filter.

## Verification and evidence

`EXSVoiceControlsTests` renders a two-tone fixture and checks actual velocity-dependent high-frequency attenuation, gain ratio, tuning, attack response and explicit smoothing. `EXSVoiceUpgradeTests` checks original hashes, exact sample/loop/range retention, recovery copies and edited-filter protection. `ModernEXSImportTests` exercises source import plus the Store update, including edited names/levels/racks and rollback. `RealtimePianoTests` checks upper-note attacks, sustained repeats and another instrument loading through the live output path. Private audio fixtures are not shipped in the repo or app.

MainStage's real-piano filtered/bypassed takes and synthetic-noise experiments confirmed the active source filter/group behavior, but do not establish an exact null match: the surrounding processing, source group transitions, recording level and noise-estimation variance affect those comparisons. The implemented native 12 dB filter response was independently measured with an impulse. Warmth and response still require a level-matched listening check against MainStage.

The bounded Swift parameter reader is independently implemented. Parameter identities were cross-checked against the [ConvertWithMoss format definitions](https://github.com/git-moss/ConvertWithMoss/blob/main/src/main/java/de/mossgrabers/convertwithmoss/format/exs/EXS24Parameters.java). Native connections use the per-layer summing semantics and cents/time-factor units described in [Apple TN2331](https://developer.apple.com/library/archive/technotes/tn2331/_index.html); [Apple's group documentation](https://help.apple.com/logicpro/mac/9.1.6/help/English.lproj/en/logicpro/instruments/chapter_12_section_16.html) describes independent group filter offsets. No third-party parser or reference implementation is bundled.
