# Offline render-budget reporting

Refs #4. Measurement structure adapted with the owner's explicit permission from `WorshipWarehouse/Clean-Room-SK` commit `554661c0665f082713003a45d92db468879fa92a`, `Tests/SundayKeysCoreTests/RenderBudgetTests.swift`. StageKeys' existing C processors are measured; no Clean-Room DSP or vendor assets are copied.

```
Tools/measure-render-budget.sh /private/tmp/stagekeys-render-budget-NEW
```

The output directory must be new and outside the checkout. The script compiles with clang `-O2` and retains `metadata.json`, `build.log`, the executable and `report.json`. Metadata includes revision/dirty state, exact input hashes including the ShimmerPitch header, OS, architecture, compiler and hardware model when readable. A restricted environment records null for an unavailable hardware model. Record interface/driver, background load and thermal/power conditions separately before comparing controlled runs.

The report contains 54 rows: 44.1/48/96 kHz × 64/257/512 frames × three trials × engaged/bypassed. Every row gets fresh effect state and identical generated 220 Hz stereo input (left amplitude 0.03, right 70% of left). Sixty warm-up blocks are discarded and 240 blocks measured with `mach_absolute_time`. Only `sk_process_effects_stereo` is timed; input generation, validation, sorting and output happen outside that interval. Each engaged state has the real three slots configured as Chorus (kind 5, parameter 0 = 0.4), Delay (kind 3, parameters 0 = 0.35 and 1 = 0.25), and Silver Reverb (kind 16, parameter 0 = 80 ms). All other settings use the current C defaults. The three `sk_effect` amounts are 1. The bypass comparison uses fresh states with no effect enabled. Trial order alternates engaged/bypassed first.

Rows report median, nearest-rank p95, worst block, each value's fraction of `frames/sampleRate`, over-deadline count and output peak. Finite/nonzero output and report shape are checked. Time is reported rather than treated as a portable CI pass threshold: even one missed deadline remains visible, and a good median must not hide it. No thresholds are relaxed to dismiss scheduler preemption. These are offline durations, not measured device underruns or round-trip latency.

On 16 November 2026 the local arm64 Mac completed all 54 rows with zero observed over-deadline blocks. Engaged median durations ranged approximately 9–77 microseconds; the maximum observed worst-block/deadline ratio was below 0.05 in that run. This is a short, uncontrolled-background observation, not an improvement claim or a cross-machine baseline. Raw evidence remains in the external run directory; hardware model lookup was restricted. Use the script to generate fresh evidence on each target rig.

This tool is opt-in and does not change callbacks, DSP, the app build, CI gates or test inventory. It measures a single stereo effects chain only: no sampler, hosted AU, full rack/polyphony, UI traffic, memory tracking, hardware route or soak. Existing `EffectStressTests` continues to cover all descriptor endpoints and irregular blocks. #4 remains open for full-path resource budgets and eight-hour hardware soaks; #192/#123 need their own sampler lifecycle and live-recovery verification.
