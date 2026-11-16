# Clock regression reuse

Refs #111 and #15. Test scenarios adapted with the owner's explicit permission from `WorshipWarehouse/Clean-Room-SK`, commit `554661c0665f082713003a45d92db468879fa92a`, `Tests/SundayKeysCoreTests/StepClockTests.swift`. No recovered vendor code or sound content is included. StageKeys retains its current scheduler, ownership keys, bounded stall policy and phase-preserving tempo behavior.

`MIDIFXTimerTests` now exercises 200 repeated-pitch boundaries at full gate, asserting the prior generated key is released before the next attack at the same timestamp, and that an identical tick cannot double-trigger. It also checks rejected nonfinite/backward clocks, 201 scheduled attacks across nine tempo/subdivision combinations with fixed dispatch lateness and no timestamp drift, a two-minute stall with bounded output, key release, idle restart and Panic cleanup. Existing deadline/lookahead, timestamp, tempo/groove and delivery checks stay intact.

Run from the checkout with a fresh external build directory:

```
python3 Tests/run-local-library.py . /private/tmp/stagekeys-clock-check MIDIFXTimerTests MIDIFXTests GrooveTests MIDIAudioTimelineTests
```

On 16 November 2026 all four focused programs passed on the local arm64 Mac with no skips. Gate inventory and runner regressions passed. These are deterministic scheduler tests, not measured Timer jitter, hardware latency or physical-device qualification. No production code, data format or app target changes. Neither #111 nor #15 closes: all-consumer sample accuracy, migration and sustained physical MIDI/patch-change checks remain separate acceptance work.
