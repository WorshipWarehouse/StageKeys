# AGENTS.md — StageKeys contributor and model-agent guide

## Project at a glance

StageKeys is an independent native music-performance app for macOS and iPhone/iPad, written primarily in Swift with C audio/DSP code. It provides a live instrument rack, MIDI processing, effects, sample/AU instrument support, setlists, patches, snapshots, and selective import/conversion of user-authorized MainStage and sampler content. It is an ongoing compatibility project, not a 1:1 Sunday Keys clone. See `README.md` for the product overview and `Docs/PARITY-STATUS.md` for evidence and limitations.

## Source-backed reverse-engineering summary

The checked-in records describe a bounded, evidence-led process against an accessible, signed-in Sunday Keys 2.5.2 Mac app in Demo Mode, local app resources that were accessible for read-only inspection, and selected user-authorized MainStage/sample materials. The recorded work includes:

- Observing screen layouts, control names/ranges, menu behavior, and edit/Confirm/Discard workflows; documenting what was visible and what was blocked by Demo/Prime entitlements.
- Read-only inspection of accessible app metadata and serialized preset/sample references, plus bounded inspection of selected MainStage/EXS documents. For example, `Docs/SOUND-FORMATS.md` inventories formats and references without copying sample payloads; `Docs/DEEP-UI-AUDIT.md` records observed UI behavior.
- Building independent Swift/C implementations and using generated fixtures, audio renders, tests, hashes, and calibration data to compare specific behaviors. Attribution and third-party notices are retained in `Licenses/`.
- Recording uncertainty explicitly. Matching a control or identifying a processor family is not proof of identical implementation or sound. Automated tests against an upstream MIT implementation establish that comparison only—not equivalence with Sunday Keys.

This is a summary of repository records, not a claim to have received or reviewed an original ChatGPT transcript. The repo records no proprietary source-code recovery, decryption, entitlement bypass, restricted-download access, or redistribution authorization. Do not add any such behavior.

## Working with multiple models or agents

Parallel model work is useful when each assignment is bounded and evidence-producing. A coordinator may delegate independent tasks such as:

1. **Reference/UI observer:** document only accessible, visible behavior and mark the app/version/license state, actions taken, and unverified surfaces.
2. **Format/parser analyst:** inspect only user-selected/authorized files; produce a format map, parser assumptions, malformed-input cases, and generated fixtures. Keep private/vendor files out of the public repository.
3. **DSP investigator:** isolate one processor/control at a time, propose measurable hypotheses, implement an independent version, and report render conditions, error metrics, and limitations.
4. **Test/reliability reviewer:** verify migration, persistence, MIDI ownership, audio-thread safety, distribution checks, and reproduction commands without changing the scope.
5. **Skeptical reviewer:** challenge whether each claim is supported, identify legal/provenance risks, and distinguish a working feature from a compatibility claim.

Give each agent a concrete question, allowed evidence, files it may change, and a requested output format. Ask for evidence and uncertainty, not a confident guess. The coordinator should reconcile contradictions against source artifacts and tests, keep one versioned evidence record, review every diff, and reject unsupported claims. Do not let agents independently modify the same files or commit private fixture data. Model consensus is not evidence; reproducible observations and tests are.

## Evidence and compatibility rules

- Keep observed facts, inferred mappings, independent implementation choices, test results, and unresolved questions distinct.
- For reference comparisons, record app/version and accessible license scope, platform, audio route/sample rate/block size, patch/instrument identity, control values, MIDI sequence, gain staging, capture method, and fixture provenance. Do not compare unmatched signal paths as if they were a null test.
- Preserve original source bytes when import semantics require it; verify hashes. Never silently flatten unsupported regions, instruments, routing, effects, or MIDI behavior. Label archives, partial translations, captures, and playable conversions differently.
- Do not claim complete parity, full compatibility, or a speed/fidelity improvement without the corresponding reproducible check and measured result.
- Do not turn observed brand/product behavior, copied controls, or an MIT-compatible upstream core into permission to copy proprietary code, art, sound assets, or trademarks.
- Do not commit private samples, user setlists, plugin state, credentials, or customer data. Generated fixtures should be synthetic and redistributable.

## Licensing and content boundaries

- No repository-root `LICENSE` was found when this guide was added. Unless/until the project owner chooses and adds a project-wide license, treat the license of StageKeys-authored code as **unspecified**; do not label the whole repository MIT or grant reuse rights by inference.
- Follow the scope written in each notice: Airwindows CreamCoat MIT (`Licenses/Airwindows-MIT.txt`), EXS parser-derived material MIT (`Licenses/EXS-Parser-MIT.md`), and the specifically scoped StageKeys DenseReverb MIT notice (`Licenses/StageKeys-Dense-Reverb-MIT.txt`). IBM Plex fonts are under SIL OFL 1.1 (`Resources/Fonts/OFL.txt`). Keep required notices with distributions.
- Sunday Keys/Sunday Sounds libraries, presets, samples, artwork, and proprietary implementation are not StageKeys assets. Their presence on a development machine or being downloadable for free does not establish redistribution permission. Keep them out of source/app distributions and public test fixtures. Use only content the user is authorized to use, for the requested local operation.
- StageKeys is an independent project. Do not imply endorsement, affiliation, or an official relationship. For legal questions, flag the issue for the owner/counsel rather than giving a definitive legal opinion.

## Current known gaps — do not imply these are answered or closed

The project has partial implementations and tests, but the release checklist and `Docs/RELEASE-ISSUES.md` still track unresolved work. In particular:

- Complete Sunday Keys UI/functionality/DSP parity is not established; Ultimate/Prime and other Demo-blocked behavior is unverified.
- MainStage conversion is partial. Unsupported synthesizers (including observed ES2, Retro Synth, Sculpture and other engines), routing, buses, effects, macros, MIDI behavior, modern EXS features, and full layered patches may not translate. A retained source archive is not a playable conversion.
- Halo Shimmer and several proprietary/source effects have independent approximations; DSP-family identification, spectral tests, or UI matching alone do not prove sonic parity.
- Physical iPhone/iPad operation, hardware MIDI/audio latency, prolonged live-use soak, some third-party AU behavior, and public signing/notarization/install qualification remain unverified as documented.
- The repo does not specify a project-wide license. Vendor sample/preset redistribution rights are not established.
- Cloud/Prime workflows are outside the current verified scope. A later AI patch builder is only a proposed independent StageKeys feature; it must use authorized content and the documented StageKeys schema.

Before changing any status, read the relevant current evidence and linked issue. The checklists are acceptance criteria, not proof of completion.

## Build and verification conventions

- The project is an Apple-platform Xcode project. `project.yml` documents XcodeGen inputs; `StageKeys.xcodeproj` is committed and the release CI notes say the committed project is authoritative for release builds.
- Read `Docs/RELEASE-CI.md`, relevant test scripts, and the affected source before selecting a check. `Tools/verify-release.sh mac <build-dir>` and `Tools/verify-release.sh simulator <build-dir>` are release artifact gates on macOS, not a substitute for the narrowest relevant test. The build directory must be outside the source checkout. `Tests/test-reverb.sh` is the documented reverb sanitizer suite on macOS.
- Keep changes focused, preserve existing user data and formats, and add/adjust a test when changing nontrivial parsing, DSP, migration, MIDI, or persistence logic. Run the directly affected check after the final edit; report unavailable hardware/platform checks plainly.
- Never run destructive release, signing, upload, distribution, or deployment actions unless the user explicitly requests them.
