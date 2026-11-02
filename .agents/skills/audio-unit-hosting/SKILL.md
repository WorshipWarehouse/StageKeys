---
name: audio-unit-hosting
description: "Investigate StageKeys AU discovery, instantiation, state, editors, topology and recovery on supported Apple platforms."
---

# Audio Unit Hosting

Inspect `ExternalInstruments.swift`, `ExternalSound.swift`, `AudioController.swift`, `PluginInterface.swift`, `PluginParameterModel.swift`, browser and Settings actions. Match components by type/subtype/manufacturer, retaining authored identity when unavailable. Registry refresh and cached operation-scoped discovery have distinct ownership; absence must be actionable rather than silently substituting an instrument.

Follow validation → recovery-journal admission → instantiation → generation/identity check → graph install → state restoration → readiness → editor handoff. Count only successful installs as ready. Preserve quarantine records if journal writes fail; do not grant global retry while an actual load owns a pending record. Inspect current admission policy: cancelled/timed-out backend requests may still consume capacity until callbacks return.

Guard late callback install/editor/state capture by patch, layer, component and operation identity. Never capture the old unit's state as the newly requested plugin. Test nil/error/timeout, supersession, reset, duplicate callbacks and retry. Logical cancellation is not a process kill or crash-isolation boundary.

Parameter trees and generic editors need stable IDs, range/unit handling, bypass and full-state save/restore. Validate custom UI presentation, dismissal and oversized scrolling interactively. Preserve routing, MIDI ownership, sample rate/channel format, render allocation and latency semantics; mono/stereo/multi-output and AUv2/AUv3 require an explicit real-plugin matrix. On iOS distinguish listed AUv3 support from unavailable desktop AUv2.

Use `AudioUnitCatalogTests`, `AudioUnitCommitTests`, `PluginRecoveryTests`, `PluginInterfaceRequestTests` and relevant generated failure tests present at the revision. [Audio validation](../../templates/audio-validation.md) records real vendor versions and physical device results. Generated AVAudioUnitSampler hooks establish host behavior only, not vendor compatibility or containment.
