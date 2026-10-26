# Sampler cold-start repair — 24 October 2026

Issue #60 was traced to `remove(channel)` performing a full graph edit even when that channel had no installed voice. Startup configures every slot, including empty slots. Each empty removal stopped the engine and restored all resident samplers, multiplying expensive sample reloads as the patch filled.

Removal now always advances the load generation (so a pending asynchronous AU load still cannot install after removal), then returns immediately for an empty channel. Actual graph changes retain the existing sampler-document reload, sample residency, controller restoration and mixer protection. No source or sample data changes, streaming shortcuts or instrument substitutions are involved.

`SamplerStartupTests` installs an original synthetic sampler, configures/removes 15 empty slots and asserts zero additional sampler restorations, continued engine running, audible rendered notes and unchanged source bytes. Real removal remains covered. Existing SamplerBoundaryRegressionTests and SamplerStreamingStressTests pass for held/looped/transposed notes, release tails, moved storage, rapid switching, missing-file reporting and bounded reload memory.

The full PR integration, built as a universal Mac Release, opened the user's existing four-instrument Piano patch and returned a usable accessibility tree in 2.6 seconds on the first process launch of this repair. The prior integration remained inaccessible for several minutes in sampler restoration. This includes UI automation/observation overhead and is a process-launch observation with the existing local sample cache, not a cold-disk or physical MIDI latency benchmark. Instruments/effects remained present and the five empty snapshot positions were visible. Wider slow-storage, large-session and eight-hour soak gates remain #2/#4.

## Patch-change follow-up

A lazy graph transaction now groups real patch changes too: the engine stops only if wiring actually changes, all necessary edits complete, and each attached sampler restores once before audio restarts. Pending AU load generations remain independent. The failure path restores the remaining graph and attempts to restart audio before surfacing the error. After restoration, Store reapplies the requested patch gain/pan, preventing protected old mixer values from overriding new settings. No-op batches do not stop the engine.

The strengthened startup test verifies three samplers restore exactly once each during a multi-channel batch, and that a thrown operation leaves surviving instruments and the audio engine available. The real three-instrument Steinway comparison opened in 8.3 seconds; Steinway→four-instrument Piano switched in 1.7 seconds and Piano→Steinway in 4.4 seconds. These are UI-automation observations including observation overhead, under concurrent builds, rather than guaranteed latency budgets. Slow-storage and much larger instruments still need preloading/progress qualification under #2/#4.
