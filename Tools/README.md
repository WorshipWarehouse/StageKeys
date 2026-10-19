# Native MainStage conversion

Import a MainStage `.patch` in StageKeys, then choose its original EXS/sample folder. Each supported sampler channel becomes a separate library sound with its supported effects, macros, MIDI range/transpose, pan and sustain settings attached. The saved library layer is the complete reusable sound; adding it to another patch retains those settings. Review conversion notes: private synthesizers, non-unity fader tapers, unrecognized MIDI processors and auxiliary buses still need work.

`ConvertMainStageLibrary.swift` stages a whole source archive in a **new** data folder, never overwriting an installed library. Build with the non-UI source list and native object files used by `Tests/test-library.sh`, replacing its test main with this tool. Run:

```
ConvertMainStageLibrary patchFolder sampleRoot NEW-outputFolder report.json
```

The report distinguishes staged channels from unsupported instruments and missing assets. Staged channels are not a claim of exact audio parity. The tool retains original patches and EXS bytes and references/copies original audio without resampling. Source assets and reports belong in the separate private library workspace.

# Native MainStage source inspection

The current no-resampling path is documented in [MAINSTAGE-NATIVE.md](../Docs/MAINSTAGE-NATIVE.md). Compile the read-only inspector with:

```sh
xcrun swiftc Sources/MainStagePatch.swift Tools/InspectMainStage.swift -o /tmp/InspectMainStage
/tmp/InspectMainStage /path/to/selected/patch-or-library /path/to/private/report.json
```

This inspects source data without loading plug-ins or opening MainStage. The app's import panel retains source bundles and reports unsupported processing. It does not yet publish a fully translated playable MainStage patch. Reports and source assets remain personal and must not be committed.

The capture instructions below are historical tooling; they are not used by the native import workflow.

# MainStage capture conversion

MainStage `.patch` bundles contain channel-strip `.cst` instrument/effect settings, not standalone sample audio. StageKeys cannot load ES2, Retro Synth, Sculpture or other MainStage-only instruments directly. This tool converts **Auto Sampler captures** of those patches into managed Apple AUSampler `.aupreset` instruments with their audio copied into StageKeys. MainStage is needed to create the capture, but not to play the converted sound.

On Mac, compile from the StageKeys source folder:

```sh
clang -std=c11 -O2 -c Sources/Synth.c -o /tmp/stagekeys-capture-synth.o
xcrun swiftc -import-objc-header Sources/Bridge.h Sources/MIDIControlTarget.swift Sources/Models.swift Sources/ChannelSettings.swift Sources/AudioEffectParameters.swift Sources/MIDIPrograms.swift Sources/ExternalSound.swift Sources/EXSCaptureCompatibility.swift Sources/BuiltinEffectUnit.swift Sources/ExternalInstruments.swift Sources/ExternalMIDIOutput.swift Sources/SoundLibrary.swift Sources/LibraryBrowserModel.swift Sources/SamplerInterchange.swift Tools/ConvertMainStageCapture.swift /tmp/stagekeys-capture-synth.o -framework CoreMIDI -o /tmp/ConvertMainStageCapture
```

Create a JSON manifest with one or more jobs. Use absolute paths. `notes` and `velocities` describe playback checks, not which notes will be captured. `seconds` is optional (2–30; default 2). `requireSustain` also requires audible audio during the final second. `extendKeyRange: [21, 108]` optionally widens only the outer zones for an 88-key instrument; these outer notes transpose the nearest recorded sample rather than representing additional captures. `exportFolder` is optional and must be a new folder; its parent must already exist.

```json
{
  "jobs": [{
    "preset": "/path/to/AutoSamplerInstrument.exs",
    "sampleRoot": "/path/to/its/recorded/sample/folder",
    "name": "The Base Warm Pad · Sampled",
    "collection": "Sunday Free Native · Volume 2",
    "notes": [21, 36, 48, 60, 72, 84, 96, 108],
    "velocities": [32, 64, 100, 127],
    "seconds": 12,
    "requireSustain": true,
    "exportFolder": "/path/to/new/PortableInstrument"
  }]
}
```

Test with an isolated data directory first:

```sh
/tmp/ConvertMainStageCapture /path/to/jobs.json /path/to/test-library /path/to/report.json
```

To install verified sounds locally, quit StageKeys, then run the same command with `"$HOME/Library/Application Support/StageKeys"` as the data directory. Existing entries are retained; repeated imports of the same EXS bytes are skipped. Reopen StageKeys and select Sunday Free in the sound browser. The converter preserves source files, copies samples into Imported Sounds, and writes the library atomically after audible finite playback passes. Failed imports are reported and their new managed assets removed. Do not run two library writers simultaneously.

Modern MainStage exports use extended EXS sample filename/path fields. StageKeys makes a temporary compatibility copy with short sample names so Apple's standalone sampler can resolve them. Zone, group, velocity and loop data are retained through Apple's EXS loader; the original EXS and samples remain unchanged. References must resolve inside the explicitly selected sample folder.

For capture, isolate the scratch concert from hardware program changes (Concert Inspector → MIDI → Program Changes Device → None), verify the intended patch remains selected, and avoid other MIDI performances feeding the sampled channel. Then import the free patch into a scratch MainStage concert, insert Utility → Auto Sampler after its channel effects, select range/sampling interval/velocity layers, and capture to a new EXS. MainStage places recorded samples under Music/Audio Music Apps/Samples/Auto Sampled. For pads use long sustain and crossfaded loops. For arps, sequences, layered patches, aux sends and modulation-dependent sounds, translate or capture their behavior separately; a sampled tone does not preserve arbitrary live synth controls, tempo-synced behavior or the full patch configuration.

An exported folder contains Instrument.aupreset and Samples. StageKeys' Import Sampler Library Folder can import it without MainStage. If moved, re-import to relink the sample paths. Converted private sound assets are not included in the application/source archives.

## Full free archive conversion queue

`PlanFreeArchive.py catalog.json StageKeysDataDirectory captureFolder outputFolder` creates a resumable queue for the installed archive. It checks every source against its stable library identity, records original host instruments and flags rhythmic/layered sounds for separate behavior review. `volume-NN-ready.json` includes only captures that exist and have not yet been installed. Run the converter against these manifests after capture finishes; regenerate the plan after conversion. A capture-ready file is not playable until audible validation succeeds.

Capture filenames include volume and archive identity to avoid collisions. Converter jobs may include `sourceArchiveID` and optional `tags`; verified conversions then appear as Playable under their original MainStage Archive entry. Source patches and native entries remain separate. This queue does not automate MainStage or recreate its private synthesizers. Tone sampling does not preserve editable synthesis, arbitrary modulation or rhythmic behavior.
