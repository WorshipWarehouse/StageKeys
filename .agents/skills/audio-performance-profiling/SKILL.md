---
name: audio-performance-profiling
description: "Measure StageKeys audio CPU, memory, render timing or latency with repeatable baselines and explicit hardware limits."
---

# Audio Performance Profiling

Define the hypothesis and acceptance threshold before profiling: which operation, expected improvement and failure metric? Inspect the affected render/control path and `Docs/PUBLIC-RELEASE-CHECKLIST.md`/linked performance issues. Record commit, build optimization, OS/device, interface/driver, route, sample rate, buffer size, patch/instrument/plugin versions, voices, MIDI sequence, effects, gain staging and background load.

Use Instruments Time Profiler for CPU attribution and Allocations for allocation/lifetime behavior on an authorized local run. Record tool/template/version, capture duration, warmup and repeated trials. Observe render deadline/underrun or timestamp evidence where available; UI responsiveness and average CPU are not glitch measures. Do not put logging or allocations into the callback to measure it. Instrument control-thread allocation separately from render-thread work.

Compare matched before/after paths at representative sample rates/block sizes and layered sustain/tail stress. Measure resident/peak memory and retained requests/graphs separately; a bounded queue count is not a memory ceiling. Include cold/warm loading and cancellation, external-storage behavior and long-duration drift. Report median/range and outliers with raw artifacts or hashes, not a single favorable number.

For round-trip latency document MIDI/audio timestamp method, loopback/capture hardware, calibration and uncertainty; offline block speed is not hardware latency. Use [audio](../../templates/audio-validation.md) and [hardware](../../templates/hardware-testing.md) templates. A generated DSP correctness test or simulator build does not prove a performance improvement. If hardware/Instruments access is unavailable, provide a reproducible plan and mark measurements unexecuted; never invent benchmark results.
