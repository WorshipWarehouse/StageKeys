# MainStage compatibility matrix — revision 1

2026-10-29; independent StageKeys implementation. “Active” means implemented processing, not identical Apple/Sunday Keys sound. Original source bytes are archived. Physical iPad behavior is unqualified unless separately recorded.

| Source feature | Current behavior | Evidence / limitation |
| --- | --- | --- |
| Legacy and modern little-endian EXS maps | Supported subset | Generated EXS conversion/playback; existing source-specific tests may explicitly skip without private fixtures |
| Big-endian / unknown chunk layout | Rejected | Bounded parser; no fallback map |
| Note/velocity/root/sample regions | Active | Native mapping, zone/group/range tests |
| Source global envelopes and voice controls | Active approximation | Native envelope/velocity/filter tests; exact source amplitude law remains open |
| Supported controller/velocity groups | Active | Native group/controller tests |
| Round-robin, release-trigger, nonzero crossfades | Rejected | EXS group guards; not flattened |
| Reverse, one-shot, unpitched and unsupported loop modes | Rejected | Zone guards; release-to-end remains unimplemented |
| Separate supported attack/loop regions | Active subset | Lossless PCM assembly; original files unchanged; transition response is engine dependent |
| ES2, Retro Synth, Sculpture, Alchemy | Archive-only / explicit unsupported | No independent compatible synth engine; an archive is not playable conversion |
| Saved third-party Audio Unit | Hosted when unambiguous and installed | Original plug-in state values retained; AUv2 cannot travel to iPad |
| Channel fader/pan/mute/sustain/range | Active supported fields | Source-backed fader evidence; routing/expression gaps explicitly reported |
| EQ, compressor, SilverVerb, ClipDist, stereo/synced delays | Active independent approximations | MainStageProcessingTests and effect/audio regressions; exact transfer/decay/topology remains #10 |
| Tape Delay clean static subset | Active independent timing/feedback/filter/Dry/Wet translation | Source-backed serialized-control observations and stereo impulse tests; modulation/freeze/diffuse modes rejected; not exact tape DSP |
| Linear supported Smart Control CC mappings | Active subset | Bounds/inversion/channel tests; unsupported curves/scripts reported |
| Buses, sends, patch-level output chains | Not flattened; reported | Full routing translation remains #6 |
| Multiple sampler instruments in one channel | Explicit unsupported topology | Separate layers cannot be asserted equivalent to shared nonlinear processing |

This matrix is a support policy and evidence index, not blanket validation of every source record. Unsupported/unknown payloads must remain in archives and warnings; no substitute oscillator or resampling is used for native EXS conversion.
