# Open-source effects integration roadmap

StageKeys keeps one native C render architecture. Third-party work enters only
when its license is distribution-compatible, its source can be isolated from a
plugin framework, and matched tests demonstrate a benefit. Existing patches
retain versioned legacy processors; choosing a new processor is explicit.

| Effect family | Current direction | Upstream evaluation | Status |
|---|---|---|---|
| Stage Reverb | Independent eight-line FDN; Room, Hall, Ambient | Airwindows Galactic2, Verbity2 and plates (MIT) | Reverb 2 profiles active; upstream prototypes pending listening tests |
| Chorus | Two-voice stereo triangle-LFO delay | DaisySP Chorus (MIT) | `stage-chorus-v1` active for new instances |
| Delay | Existing stereo/synced engine | Signalsmith delay/interpolation (MIT) | Evaluate higher-order interpolation without adding render allocations |
| Flanger | Existing short modulated delay | DaisySP/Signalsmith primitives (MIT) | Planned after Chorus listening and CPU qualification |
| Shimmer/Pitch | Existing bounded StageKeys engine | Signalsmith Stretch (MIT) | Research only; latency and allocation model must fit live use |
| Overdrive/Saturation | Existing antialiased processors | Selected Airwindows processors (MIT) | Candidate shootout pending |
| Rotor | Existing native model | Permissive rotary/Leslie candidates | Dependency and listening audit pending |
| EQ, compressor, gain, tone, tremolo, bitcrusher | Independent native processors | Reference test suites rather than wholesale replacement | Retain unless a candidate wins measured tests |

ChowMatrix is BSD-3-Clause, but its plugin and supporting modules are closely
coupled to JUCE and include separately licensed components. StageKeys will not
vendor the complete project. Any matrix-delay work requires a file-level audit
and a small framework-independent adaptation.

Every integration requires: a bundled notice, pinned upstream provenance,
finite/bounded output tests, bypass and Panic tests, parameter smoothing,
44.1/48/96 kHz coverage, preset round-trip coverage, matched CPU measurements,
and level-matched listening on piano, organ, synth and pad sources. Offline
correctness does not establish physical iPad stability.
