---
name: performance-engine
description: "Change StageKeys rack, layers, patch/snapshot/setlist behavior or instrument resource recovery during performance."
---

# Performance Engine

Trace Store user intent to `AudioController` and `ExternalInstrumentRack`; read `Models.swift` and `SnapshotMorph.swift` for document semantics. The performance rack has 15 sound positions plus Tonic on channel 15. Preserve layer identity, keyboard ranges, gain/mute, controller state and authored snapshot data through replacement.

Before mutation identify what is reversible: resource preflight, loading, graph install, plugin state restoration, MIDI ownership, persisted commit and UI readiness are different phases. Inspect current recovery documents under `Docs/` and tests before assuming all changes are atomic. A saved source archive is not a playable conversion and a pending AU is not a ready instrument.

Guard asynchronous work by operation token, patch identity and layer identity. Superseded callbacks must not attach, persist or open editors for newer selections. Account for timers and transition generations on Stop, patch changes, interruption and failure. Avoid replaying stale snapshot gain frames into a newly selected document. Restore controllers/held notes deliberately; replay may retrigger an envelope and does not preserve DSP phase.

Keep native-only fast paths and resource admission limits explicit. Stop and logical cancellation do not prove a backend request ended; do not release capacity merely to allow unlimited retries. Manual Stop must not be undone by discovery or incidental UI refresh.

Run relevant `StoreTests`, `PatchReadinessTests`, `SnapshotLifecycleTests`, `SnapshotProcessingTests`, `ResourceAvailabilityTests` and Tonic tests available at the target revision. Use [regression](../../templates/regression-testing.md) to cover rapid switch, held sustain, missing files, stale callbacks and recovery. Mark physical performance/soak criteria unverified until measured.
