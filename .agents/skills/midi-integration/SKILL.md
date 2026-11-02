---
name: midi-integration
description: "Fix StageKeys MIDI input/output, controller routing, ownership or musical event ordering with deterministic and hardware checks."
---

# Midi Integration

Trace `MIDIInput.swift` → `PerformanceStore.handleMIDI` → `MIDIFXProcessor.swift`/audio and `ExternalMIDIOutput.swift`. Inspect `MIDIPrograms.swift`, `MIDIControlTarget.swift` and the current controller setup model. Confirm protocol handling before adding MIDI 2.0: API availability alone does not establish UMP support across the app. Preserve MIDI 1.0 byte parsing, running/packet boundaries and channel conventions; UI labels may be one-based while stored values are zero-based.

Treat note-on velocity zero as note-off where required. Track source/channel/note ownership through repeated pitches, splits, transpose, Easy Chord/sequencer output and external destinations. Note-off must release the original routed note even after settings change. Cover CC64 sustain, modulation, pitch bend, CC7/11, all-notes-off and explicit Panic; document unsupported half-pedal/sostenuto instead of silently claiming it.

Hot-plug/disconnect must release only relevant source ownership and never implicitly select a patch. Preserve explicit Program Change opt-in, Patch Lock, learned CC filtering and manual audio Stop policy. Capture event order around patch switches and startup; discovery callbacks must not resurrect intentionally stopped audio.

Use existing virtual CoreMIDI tests (`MIDIInputTests`, `PlugAndPlayTests`, `ProgramChangeOptInTests`, `ExternalMIDITests`, `MIDIFXTests`) through the library runner. Add deterministic source/channel sequences for the defect. Hardware validation records controller/model/firmware, route, monitor events, power-cycle timing and audible result using [MIDI validation](../../templates/midi-validation.md). A synthetic device pass does not close a physical keyboard reproduction criterion.
