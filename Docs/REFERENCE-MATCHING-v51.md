# Native import and reference matching — 0.51

MainStage `.cst` channel strips now enter the same native EXS conversion workflow as `.patch` bundles. Original channel-strip bytes and samples are retained without resampling or opening MainStage. A bare strip explicitly reports missing parent-patch buses, sends and patch-level MIDI; it is not advertised as a complete patch. Unsupported instruments and processing remain compatibility blockers.

Sound Settings → output matching now accepts an RMS target from −60 to −6 dBFS. **Use Matched Level as Reference** reuses the proposed output level for later instruments in the current app session. Targets can be revised without rerendering. The isolated probe now uses the patch tempo for synced effects. Review and apply the proposed trim; it never silently changes source presets. RMS matching is not perceptual LUFS normalization, and sample-peak protection is not true-peak limiting. Different articulations, ranges and velocity curves still need listening checks.

SilverVerb now damps successive late-tank feedback passes, rather than filtering only their finished output. On one saved MainStage capture, normalized three-band decay error improves from 3.775 to 2.272 dB. Wideband envelope error changes from 0.467 to 0.729 dB: a documented tradeoff, not exact parity. Early reflections are unchanged. See [measurement evidence](Calibrations/Steinway-Reverb-Bands-v51.json). Original sampler gain/velocity translation and sample data are unchanged.

Verification: native bare-CST and bundle conversions with the private Steinway fixture; exact retained CST bytes; gain-target regressions and an actual hosted AU; sanitizer reverb/Shimmer tests at 44.1/48/96 kHz; universal Mac and iOS Simulator release builds. No new live reference recording or physical iPad qualification was performed. Shimmer retains the existing pitch, feedback-tone, tail and Panic regressions; this release does not claim a new measured Sunday Keys Shimmer match.

Release issues #5, #9, #10, #11, #18 and #25 remain open for broader conversion, DSP, UI and instrument qualification. No bundled sound library is required to run the app.
