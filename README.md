# StageKeys

StageKeys is an independent native music-performance app for macOS and iPhone/iPad, built primarily with Swift and C. It combines a live instrument rack, MIDI processing, audio effects, snapshots and setlists, and selective import/conversion of user-authorized sampler and MainStage content.

**StageKeys is an ongoing compatibility project, not a 1:1 Sunday Keys clone.** Similar controls or processor names do not establish identical behavior or sound. See [current parity and evidence](Docs/PARITY-STATUS.md), [conversion status](Docs/CONVERSION-STATUS.md), and [open release issues](Docs/RELEASE-ISSUES.md).

**StageKeys ships without sounds.** Start with a blank patch, then import your licensed samples/sampler instruments, add an installed Audio Unit, or route MIDI to external hardware/apps. Tonic Pad also requires a user-selected sound. No demo setlist or playable factory voices are included. See [first-run setup](Docs/FIRST-RUN.md).

## What it does

- **Live performance:** 15 sound positions, layered keyboard ranges, per-sound level controls, snapshots, setlists, and an on-screen keyboard.
- **MIDI:** connected-device routing, MIDI effects, sustain, modulation, MIDI Learn, and external MIDI destinations.
- **Sound processing:** native effects, supported Audio Unit instruments, and selected imported sampler instruments.
- **Selective conversion:** inspect and translate supported sampler/MainStage content while retaining source archives and reporting unsupported behavior rather than silently dropping it.

The app has substantial working functionality, but complete UI/DSP parity, unsupported synthesizers and processing chains, physical iPhone/iPad operation, hardware latency, prolonged live-use testing, and public distribution qualification remain incomplete or unverified. Read the [parity status](Docs/PARITY-STATUS.md) and [public-release checklist](Docs/PUBLIC-RELEASE-CHECKLIST.md) before relying on compatibility claims.

## Build and run

- Requires Xcode and Apple platform SDKs. The project targets macOS 13+ and iOS/iPadOS 16+.
- Open [`StageKeys.xcodeproj`](StageKeys.xcodeproj) in Xcode and choose `StageKeysMac` or `StageKeysMobile`. Physical-device installation requires your Apple development team.
- `project.yml` documents XcodeGen inputs; the committed Xcode project is authoritative for release builds.
- For local release verification on macOS, follow [`Docs/RELEASE-CI.md`](Docs/RELEASE-CI.md). Build artifacts must be placed outside the source checkout.
- See [`Tools/README.md`](Tools/README.md) for conversion tooling and its limitations. Import only content you are authorized to use; private and vendor sample libraries are not included in app distributions.

## Reverse-engineering and evidence

The repository records an evidence-led investigation of the accessible Sunday Keys 2.5.2 Mac app in Demo Mode, selected read-only app metadata, and user-authorized local formats. The work documented visible layouts and controls, examined bounded preset/file structures, then implemented independent behavior and compared it using generated fixtures, audio renders, hashes, and calibration data. Demo/Prime-restricted behavior remains unverified; no proprietary source recovery, entitlement bypass, or redistribution permission is claimed.

See the [deep UI audit](Docs/DEEP-UI-AUDIT.md), [sound-format inventory](Docs/SOUND-FORMATS.md), [MainStage conversion notes](Docs/MAINSTAGE-NATIVE.md), and [audio fidelity evidence](Docs/PIANO-FIDELITY.md). The records summarize the project evidence; they do not claim to reproduce an original ChatGPT transcript.

For coordinated model or specialist work, give each contributor a bounded question, allowed evidence, isolated files, and a requested output format. Useful independent roles include visible-UI observation, authorized-format analysis, one measurable DSP investigation, and skeptical evidence/licensing review. A coordinator should reconcile claims against source artifacts and reproducible tests. Model consensus is not evidence. See [`AGENTS.md`](AGENTS.md).

## Licensing and content

**This repository has no root project-wide `LICENSE`; the license for StageKeys-authored code is unspecified here.** Do not assume the whole app is MIT-licensed or infer reuse permission. The project owner’s license decision is tracked in [issue #64](https://github.com/WorshipWarehouse/StageKeys/issues/64).

Third-party notices apply only to their stated components and scopes:

- Airwindows CreamCoat: MIT — [`Licenses/Airwindows-MIT.txt`](Licenses/Airwindows-MIT.txt).
- EXS parser-derived implementation: MIT — [`Licenses/EXS-Parser-MIT.md`](Licenses/EXS-Parser-MIT.md).
- StageKeys DenseReverb: MIT for only the specifically scoped code — [`Licenses/StageKeys-Dense-Reverb-MIT.txt`](Licenses/StageKeys-Dense-Reverb-MIT.txt).
- IBM Plex Sans fonts: SIL Open Font License 1.1 — [`Resources/Fonts/OFL.txt`](Resources/Fonts/OFL.txt).

Keep required notices with distributions. Sunday Keys/Sunday Sounds libraries, presets, samples, artwork, and proprietary implementation are not StageKeys assets; a local copy, free download, or ability to import does not establish redistribution permission. See [distribution provenance](Docs/DISTRIBUTION-PROVENANCE.md) and [free-patch audit](Docs/FREE-PATCHES.md). StageKeys is independent and does not claim affiliation or endorsement.

## Project records

- [Parity status and implementation evidence](Docs/PARITY-STATUS.md)
- [Public release checklist](Docs/PUBLIC-RELEASE-CHECKLIST.md)
- [Release issue index](Docs/RELEASE-ISSUES.md)
- [Change history](CHANGELOG.md)
