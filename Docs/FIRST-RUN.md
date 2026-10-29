# First run: bring your own sounds

StageKeys ships without sounds or a demo setlist. A new profile opens My Setlist with one New Patch, fifteen Add Sound positions and five empty snapshot positions. No MIDI level assignments or Program Change mapping is pre-bound.

Choose Import Samples to add your licensed audio/sampler files. Choose Add Sound → Audio Units to select an instrument already installed on the device, or External MIDI to route notes to hardware/another host. Until then, the keyboard is a controller and produces no musical audio. The metronome and effects controls are utilities, not a factory sound library.

Tonic Pad also starts without a sound. Open Tonic Pad Settings → Choose Sound, or import a supported looped sampler instrument. Turning on an empty pad explains what is missing instead of generating a fallback tone.

Existing imported sounds, plug-in references, effects, tags, snapshots and samples are retained. Obsolete factory-voice indices in older user documents remain as metadata, but are unavailable; replace them using Add Sound. No instrument is substituted and the original samples are not rewritten.

The C synthesis routines remain implementation/DSP-test code because the same core supplies effects and clock processing. No Swift product note route calls those musical generators. Test-only FixtureSupport.swift creates explicit synthetic samples and setlists at runtime; neither app target compiles it or bundles those files.

NoFactorySoundsTests verifies clean-profile structure, silence under note/pedal/pad/legacy-index requests, save/reload, unchanged legacy metadata and unchanged playable imported samples. The distribution gate rejects sampled content and known factory-catalog/generator entry markers in product source/bundles; it is a backstop, not a substitute for runtime regression or provenance review.

Verification for #89: the final 79-entry local corpus reports 68 exercised passes and 11 explicit private-fixture skips, with no failures. Universal Mac and iOS Simulator Release artifact gates, portable processing checks and reverb/effect ASan/UBSan pass. Neither app executable contains test fixture support. The blank-install invariant fails against the previous compiled main. No physical iPad or source-fidelity claim is implied by these checks.
