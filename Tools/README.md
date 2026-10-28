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

# Sampler calibration evidence

[Docs/SAMPLER-CALIBRATION-GATE.md](../Docs/SAMPLER-CALIBRATION-GATE.md) defines the steady-level gate that compares a converted sound against its MainStage reference. `Tools/verify-sampler-calibration.py` validates a declared measurement document and never adjusts audio or gain:

```sh
python3 Tools/verify-sampler-calibration.py evidence.json   # notes 60/74/86, velocities 1–127, pedal off/on, isolated/chord
python3 Tools/verify-sampler-calibration.py smoke.json --notes 60,86 --velocities 38,127
```

The default matrix is 1524 measurements, and a document must declare exactly the grid it is checked against — a row outside it is refused rather than ignored. A smaller explicitly requested grid is useful during calibration but does not establish full-velocity coverage. Schema 1 requires matching original instrument, sample and zone-map hashes for both hosts, StageKeys output headroom declared separately from source/channel/bus gain, and a selected source zone per measurement. The report echoes the declared setup and the measured level error after only that headroom allowance, and it exits 0 only when every row is present and within 1 dB, 1 when rows are missing or the error exceeds it, and 2 when the evidence itself is invalid.

Declaring the setup is not the same as being isolated, so the checker validates it instead of accepting its presence. Evidence that claims dry steady levels while channel EQ or effects are active is refused rather than re-reported as a smaller error, as is a non-finite or boolean source/channel/bus gain, or one outside a ±48 dB plausibility window. Source gain and bus gain may legitimately be nonzero; the refusal is for undeclared, hidden or compensating values.

This measures steady RMS only. Attack/decay, layer transitions, timbre and physical latency need separate reviewed recordings, and passing the gate is not a parity claim. The checker's own tests are synthetic, and the evidence plus the audio it refers to stay outside this repository.

# Preset archive audit

`Tools/audit-mainstage-presets.py` inventories a captured MainStage archive without opening MainStage, loading a plug-in or changing samples:

```sh
python3 Tools/audit-mainstage-presets.py /path/to/archive /path/to/sound-library.json > audit.json
```

Every top-level `.patch` is read, nested template patches are skipped, and each channel strip is hashed and matched against the library's `mainstage-channel-<sha256>-<n>` IDs. A channel with no match is `archived-only`; an unreadable, oversized, symlinked or path-escaping document is `blocked` with its reason rather than dropped. The summary counts patches, channels, native-channel occurrences, patches with complete coverage and blocked patches, and its `limitations` block says coverage means a retained playable channel, not verified full-patch audio, routing or effect parity.

# Library tag extraction

`Tools/catalog-tags.py` turns an already exported personal catalog into the optional `source-sound-tags.json` described in [LIBRARY-CURATION.md](../Docs/LIBRARY-CURATION.md):

```sh
python3 Tools/catalog-tags.py catalog.json source-sound-tags.json
```

Only `TagType` and `Sound` entries are read — no samples, presets, account tables or processing settings. When a saved copy shares a name with its template, the template's tags win. The output maps each sound to category, type, timbre, articulation, note range, source model, complexity and the Recommended flag; unknown facets are ignored, absent ones fall back to `Other`/`Sampler`, and `inferred` stays false because nothing is guessed. A catalog over 16 MB is refused.

# Velocity capture comparison

`Tools/compare-velocity-captures.py` reproduces the host-velocity A/B analysis in [MAINSTAGE-MIGRATION.md](../Docs/MAINSTAGE-MIGRATION.md). The changed capture is the reference and the neutral one the baseline:

```sh
python3 Tools/compare-velocity-captures.py changed.wav neutral.wav --output report.json
```

It reads 16/24/32-bit integer and 32/64-bit float WAV at 44.1, 48, 88.2 or 96 kHz, keeps stereo intact, finds onsets, aligns each take by FFT cross-correlation, and reports `changedToNeutralDB`, `normalizedResidual` and `lagSamples` per note and velocity. The default sequence is notes 60/74/86 at velocities 38/64/83/102, changeable with `--notes` and `--velocities`. It needs `numpy` and never resamples or writes audio. A wrong onset count, non-WAVE or full-scale input, or a mismatched rate or channel count exits 1; invalid arguments exit 2. A paired synthetic 4 dB cut measured 4.003 dB with a 0.0007 normalized residual.

# Reverb comparison corpus

`Tools/render-reverb-comparison.c` renders the corpus behind [REVERB-ENGINES-v53.md](../Docs/REVERB-ENGINES-v53.md). Both DSP translation units are required:

```sh
clang -std=c11 -O3 Tools/render-reverb-comparison.c Sources/Synth.c Sources/CreamCoat.c -lm -o /tmp/render-reverb
/tmp/render-reverb /path/to/empty-output-folder
```

It synthesizes piano-like, organ-like, pad, synth and layered chords and renders each through the legacy and Dense engines in both core settings: 20 twelve-second stereo 48 kHz `.f32` renders, about 88 MB, with no library audio. One CSV row per render goes to stdout (`instrument,kind,dense,cpuSeconds,peak,rms`), and a non-finite sample stops the run. The peak and RMS columns reproduce the recorded corpus exactly; `cpuSeconds` is process time on one machine, so the `-O3` build and this Mac's 0.058 s worst case describe a build and a host, not a realtime deadline.

# Factory voicing application

`Tools/ApplyFactoryVoicing.swift` applies the observed Room voicing to pristine native Felt Piano modules in one named patch, as recorded in [PIANO-FIDELITY.md](../Docs/PIANO-FIDELITY.md). Build with the non-UI source list and native object files used by `Tests/test-library.sh`, replacing its test main with this tool, then run:

```
ApplyFactoryVoicing "$HOME/Library/Application Support/StageKeys" "Piano Patch" NEW-backup.json report.json
```

Only layers still carrying default channel settings, no effects, no imported rack and no MIDI program are changed, and only when their sample file matches an `SK App Felt Piano` library entry; gains, routing and other patches are untouched. The backup path must not exist yet, and `setlist.json` is rewritten only when something changed. It reports through `fatalError`, so a missing argument or an unreadable data directory ends in a crash message and a signal exit rather than a usage line and a clean non-zero exit.

# App icon generation

`Tools/GenerateAppIcon.swift` draws the StageKeys icon with AppKit:

```sh
swiftc Tools/GenerateAppIcon.swift -o /tmp/GenerateAppIcon
/tmp/GenerateAppIcon Resources/StageKeys.iconset
```

It writes `icon_16x16` through `icon_512x512@2x`, and `Resources/StageKeys.icns` is the compiled iconset. Generate into a scratch folder and compare before replacing the committed files: on a Retina display the current script draws the same artwork at twice the pixel dimensions its names promise (`icon_16x16.png` comes out 32 px), so a fresh run here does not reproduce the committed, correctly sized set.

# REA analysis records

[Docs/REA-WORKFLOW.md](../Docs/REA-WORKFLOW.md) describes how the external [REA](https://github.com/morluto/rea) toolchain is used to derive field meaning from MainStage itself, under the evidence and licensing rules in [AGENTS.md](../AGENTS.md). Keep artifacts and records in the gitignored `Analysis/` folder:

```sh
python3 Tools/rea_probe.py probe /path/to/Selected.cst --out Analysis/evidence \
  --application "Sunday Keys 2.5.2 (MainStage)" --application-version 2.5.2 \
  --license-scope "Demo Mode" --authorization "user-owned local installation" \
  --rea-command "npx -y rea-agents@6.8.0"
python3 Tools/rea_probe.py verify Analysis/evidence/*.evidence.json
```

`probe` hashes the artifact, records bounded container-literal observations and captures REA Evidence beside the record; `verify` rejects a record with no provenance, an inference citing no observation, a malformed digest, or an artifact stored inside the repository. Neither command converts a patch, launches MainStage or claims parity.

# Saved Audio Unit state

`Tools/ApplyMainStageAUState.swift` reports the Audio Unit class info a MainStage channel strip saved. With `--apply` it instantiates the matching installed component and prints the parameters the saved state changes. It never modifies the source patch, and without `--apply` it loads no plug-in.

Build with the non-UI source list and native object files used by `Tests/test-library.sh`, replacing its test main with this tool, then run:

```
ApplyMainStageAUState "/path/to/selection.patch"          # report only
ApplyMainStageAUState "/path/to/channel.cst" --apply      # apply and list changed parameters
```

A version-changed component is reported, not hidden: the saved subtype is printed next to the installed one, and the tool warns that parameter mapping between versions is unverified. State application settles asynchronously, so the tool waits before reading values back.

# Distribution provenance gate

[Docs/DISTRIBUTION-PROVENANCE.md](../Docs/DISTRIBUTION-PROVENANCE.md) records what the app distribution excludes: the private sound library, imported MainStage/Ableton samples, user setlists and AU state. `Tools/check-distribution.py` is the enforceable read-only gate for that exclusion, and it checks either a source checkout or a built app:

```sh
python3 Tools/check-distribution.py --repo /path/to/checkout        # tracked plus would-be-committed untracked files
python3 Tools/check-distribution.py --bundle /path/to/StageKeys.app # a built application bundle
```

It refuses private content by file name, extension or path component: sampled-audio extensions (`.wav`, `.aif`, `.aifc`, `.aiff`, `.sd2`, `.caf`, `.flac`, `.mp3`, `.m4a`, `.sf2`, `.dls`); sampler instruments, channel strips and host devices/sets (`.exs`, `.aupreset`, `.cst`, `.alp`, `.adg`, `.als`); MainStage documents (any `.patch` or `.concert` bundle); the data files the app writes for the user (`sound-library.json`, `manifest.json`, `setlist.json`, `setlist-v<N>-backup.json`); and anything under `Imported Sounds`. It exits 1 and lists the offending paths. A bundle must be an existing directory rather than a symlink, contain an `Info.plist` and carry the four retained notices (`Airwindows-MIT.txt`, `EXS-Parser-MIT.md`, `StageKeys-Dense-Reverb-MIT.txt`, `OFL.txt`); each missing notice is named in its own failure.

This is a name-based backstop against accidental commits, not proof that no private content is present: a file the app renames, such as a per-identity file inside a setlist library, is invisible to it. `--repo` checks the checkout as a plain `git add -A` would commit it — tracked files plus untracked files that the checkout's `.gitignore` does not exclude — so an untracked `Song.als`, `note.aifc` or `setlist-v3-backup.json` is refused instead of passing until someone stages it; gitignored private audio stays out of scope on purpose, because committing it already needs `git add -f`. It needs a real Git repository, failing with Git's own error rather than a verdict if the path is not one. `--bundle` walks files and directories alike, so an empty `.patch` or `.concert` bundle inside a shipped app is refused as well as a populated one. One target is required: with neither flag the tool prints usage and exits 2 instead of checking nothing.

`--repo` is the first step of `Tools/verify-release.sh`, which then checks the Release bundle it just built with `--bundle`, so the `builds` CI job runs both modes for `mac` and `simulator`; `Tests/test-distribution.py` exercises the refusals — untracked content, an empty MainStage document directory, a missing notice, a symlink bundle and a no-target run — against disposable synthetic checkouts in the `processing` job. `Tools/verify-public-mac.sh` runs the bundle check before signature, hardened-runtime, stapled-notarization and Gatekeeper verification. Passing this gate proves exclusion from the artifact, not redistribution rights and not a valid signature: public signing/notarization and clean-machine installation remain unverified.
