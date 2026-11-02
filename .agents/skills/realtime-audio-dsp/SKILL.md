---
name: realtime-audio-dsp
description: "Investigate StageKeys rendering, DSP, audio graph edits or glitches while preserving real-time thread safety."
---

# Realtime Audio Dsp

Read `Sources/AudioController.swift`, `ExternalInstruments.swift`, `BuiltinEffectUnit.swift`, `ImportedAudioGraph.swift`, `Synth.c` and the affected processor. Identify the actual render callback versus main/control-thread paths. Do not allocate, lock, perform file/network I/O, log, query plugin registries or edit graphs on a render thread. Prepare immutable/control data elsewhere and use the existing parameter/event handoff; audit destruction and ARC release paths as well as creation.

For DSP edits record sample rate, channel layout, interleaving, buffer size, input levels, effect parameters, smoothing and reset behavior. Bound indexing by actual frame/channel capacity. Reject nonfinite parameters and protect feedback paths. Preserve intentional gain staging and headroom; a limiter hiding a conversion error is not a faithful fix.

Graph edits must use the existing batch/rollback paths and propagate operation, reconnect, restoration and restart failures separately. Test retained playback and note ownership after rejection, not only an error return. Retired tails need bounded ownership and explicit Panic/Silence Previous behavior. Never claim a logical AU timeout preempts vendor work.

Use generated signals and renders for continuity, silence/NaN, tail and spectral regressions. For C reverb changes read and run `Tests/test-reverb.sh` (sanitizers) and affected C tests. Compare performance with [profiling](../audio-performance-profiling/SKILL.md), recording matched conditions and variance. Offline correctness cannot prove hardware underrun-free operation. Use [audio validation](../../templates/audio-validation.md); disclose independent approximations rather than claiming reference sound parity from processor names.
