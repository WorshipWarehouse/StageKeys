---
name: stagekeys-architecture
description: "Locate StageKeys subsystem ownership and trace data flow before changing app behavior or integration boundaries."
---

# Stagekeys Architecture

Start with repository `README.md`, `AGENTS.md`, `project.yml` and `Docs/PARITY-STATUS.md`. Confirm paths with `rg --files Sources Tests` and symbols with `rg -n`; this map is an entry point, not a replacement for current source.

`Sources/StageKeysApp.swift` owns SwiftUI app entry and platform scene integration. `Store.swift` contains `PerformanceStore`, observable performance state, user actions, MIDI dispatch and session orchestration. `Models.swift` contains validated Codable setlists, patches, layers, snapshots and imported processing models. Follow edits from views (`Editors.swift`, `SettingsViews.swift`, `SoundBrowser.swift`, `PerformanceControls.swift`) to Store actions instead of mutating runtime audio directly from a view.

`AudioController.swift` coordinates engine startup, channel controls, snapshots and audio failures. `ExternalInstruments.swift` owns hosted instrument lifecycle and graph transactions; `BuiltinEffectUnit.swift` and `ImportedAudioGraph.swift` implement native/translated processing. `Synth.c`, `Synth.h`, `CreamCoat.c` and `Bridge.h` form the C DSP boundary. `MIDIInput.swift`, `ExternalMIDIOutput.swift` and `MIDIFXProcessor.swift` handle device/input/output and musical processing.

`SetlistLibrary.swift`, `SessionSettings.swift`, `SoundLibrary.swift`, `LibraryBackup.swift` and Store persistence actions own archives/settings; `MainStagePatch.swift`, `MainStageProcessing.swift`, `EXSNative.swift`, `StageKeysSampler.swift` and `SamplerInterchange.swift` own selective conversion. Inspect actual callers and tests before assigning ownership. Check `#if os(...)` branches; simulator compilation does not exercise physical MIDI or AUv3.

Find adjacent tests by subsystem and the default list in `Tests/test-library.sh`. Draw the affected state/data flow, identify authoritative model versus speculative runtime state, and name failure boundaries before editing. Preserve platform dependencies and the committed Xcode project; do not add a parallel architecture merely to bypass an existing invariant.
