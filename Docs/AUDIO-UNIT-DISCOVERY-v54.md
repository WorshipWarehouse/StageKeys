# Audio Unit discovery, editors and saved state

Issue: [[P1] Finish Audio Unit discovery, editors and saved state](https://github.com/WorshipWarehouse/StageKeys/issues/12).

This increment covers discovery metadata, unavailable-plugin reporting, a generic editor for plug-ins without a custom view, and Audio Unit state capture at three points that previously lost it. It is not a claim that AU hosting is complete: out-of-process isolation, parameter automation and physical iOS AUv3 remain open and are listed at the end.

## Discovery and the instrument picker

- `ExternalAUIdentity` now carries the catalog's vendor (`manufacturerName`), `versionString`, AUv3 and custom-view flags, the auval result (macOS) and an `unavailableReason`. All new fields are optional, so setlists and library entries written before this change still decode.
- Identity equality and hashing use only the component type/subtype/manufacturer triple and display name. Catalog metadata cannot make a saved layer look like a different instrument, which would otherwise reload the plug-in whenever the picker supplied more detail than the setlist stored.
- `ExternalInstrumentRack.instruments()` enriches every music-device component, marks components with no build for this Mac's processor as unavailable (architecture list, macOS), and sorts by vendor then name through `ExternalAUCatalog`.
- `ExternalAUCatalog.matches` implements the browser's search contract over name, vendor and version, so "arturia jun" finds a vendor's instrument by either word.
- The sound library's Audio Units collection now shows the vendor on each row, keeps unavailable components listed with the reason in the footer instead of failing at instantiate time, surfaces an auval warning for components that did not pass validation, and offers **Rescan**.

Rescan re-queries the component manager. Core Audio has no public rescan API, so a plug-in installed while StageKeys is running may still need a relaunch before it appears; the button's help text says so.

Consequence: an AU marked unavailable by architecture is shown as `Unavailable` in the Availability filter and cannot be added or auditioned. auval status never blocks, because working plug-ins are frequently unvalidated.

## Editors

- `PluginInterface` waits up to four seconds for the asynchronous Audio Unit load instead of showing a permanent "still loading" screen when the sheet opens before installation finishes.
- When the plug-in returns no custom view, the sheet opens a generic editor built from `AUAudioUnit.parameterTree`: up to 256 parameters with name, formatted current value, a slider or a value menu for string-valued parameters, and a factory-preset picker when the plug-in exposes presets. Changes are written to the live `AUParameter`, and an `AUAudioUnit` parameter observer keeps the UI in step with changes made elsewhere (the plug-in's own window, host automation).
- When the Audio Unit exposes neither a view nor parameters, the sheet says so explicitly rather than showing an empty panel.

## Saved state

Three gaps are closed:

1. Closing the instrument interface used to discard edits. The channel editor runs inside an audition, `capturePluginStates` deliberately skips the auditioned channel, and `endAudition` restored the state captured when the sheet opened. `Store.finishPluginInterface` now serializes the live state into both the audition session and the layer before the sheet closes, so `endAudition` restores the edited state rather than the original.
2. `duplicate()` captured nothing before copying, so a duplicated patch could carry an older Audio Unit state than the source. It now captures first.
3. `SnapshotSoundState` did not store Audio Unit state at all, so recalling a scene left the plug-in as it currently was. Snapshots now carry `pluginState`, `captureSnapshot` captures current plug-in state before recording, and recall restores it in place through `AudioController.restorePluginState` (assigning the document state without an engine restart). Older setlists decode with `pluginState == nil`. Snapshot validation bounds the stored state at 2 MB, matching layer validation.

Identity, MIDI routing (`midiDestinationID`, `midiOutputChannel`) and per-sound MIDI program were already part of the layer and snapshot data and are unchanged.

## Tests

- `Tests/AudioUnitCatalogTests.swift` (added to `Tests/test-library.sh`, no plug-ins required): legacy identity decode, identity equality/hash stability under catalog metadata, metadata round-trip, different-component/name detection, vendor-then-name ordering, unavailable components staying listed, vendor+name search, and `SnapshotSoundState` carrying state while decoding setlists that predate it.
- `Tests/AudioUnitTests.swift` (requires an installed AU such as OB-Xd): unchanged load/state/MIDI/audio coverage, plus a bounded check that requesting the interface completes and reports either a view or no view, and that the parameter tree survives a document-state round trip.

Run on a Mac:

```sh
Tests/test-library.sh AudioUnitCatalogTests
Tests/test-library.sh AudioUnitTests      # needs OB-Xd or an equivalent installed AU
Tests/test-library.sh                     # full offline suite
```

## Verification status

Not built or executed: this change was prepared on Linux without Xcode, Core Audio or any Audio Unit. The touched sources and tests parse cleanly under a Swift 6.0.3 toolchain, but they have not been type-checked against Apple's frameworks, and no plug-in was hosted. Treat the following as pending:

- `xcodebuild` for both targets, then `Tests/AudioUnitTests` with a real AU.
- Manual pass with one AU that has a custom view, one without (generic editor), and one that exposes factory presets: open the interface, change parameters, close with Done, switch patches, duplicate, save and recall a snapshot, then compare state and sound.
- The unavailable-architecture path needs a deliberately mismatched plug-in (for example an Intel-only AU hosted under an arm64 build) to confirm the row and footer text.

## Remaining gates (unchanged by this work)

- Hosted-plug-in crash isolation and out-of-process loading belong to issue #13; loading is still in-process.
- Physical iOS AUv3 hosting and editors belong to issue #14.
- AU parameter automation and MIDI learn mapping onto plug-in parameters are not implemented; the generic editor writes parameters directly.
- There is no embedded editor inside the channel strip, and no preset browsing beyond the plug-in's factory presets.
- Rescan cannot make Core Audio re-scan a newly installed Audio Unit without a relaunch.

## Mac verification follow-up — 23 October 2026

Universal Mac and iOS Simulator Release builds pass after correcting the AUAudioUnit editor receiver, registering/removing observers on the retained AUParameterTree, using AudioComponentFlags.isV3AudioUnit, and guarding macOS-only custom-view metadata. A generation token prevents an old unit's queued callback from changing a newly attached editor. The generic model is separated into PluginParameterModel.swift and included in both application targets and regression builds.

PluginParameterModelTests passes against real AU parameter-tree callbacks, clamped writes, unit replacement and observer removal. Catalog and effect-preset/snapshot serialization tests pass. The hosted instrument test ran OB-Xd: custom editor resolved, 97 parameters and 128 factory presets were reported, MIDI/offline audio rendered (peak 0.13084845), document state round-tripped and obsolete asynchronous loads were cancelled. The harness now uses an isolated data directory and imports CoreAudioKit; Apple DLS is the fallback if OB-Xd is unavailable.

This does not qualify out-of-process isolation, physical iOS AUv3, every plugin's parameter semantics, or every manual snapshot/editor workflow. Those remain release work.
