# REA analysis workflow for MainStage work

Status: analysis tooling, not a compatibility claim. Nothing here converts a patch, adds a native engine or changes a row in [MAINSTAGE-COMPATIBILITY-v1](MAINSTAGE-COMPATIBILITY-v1.md). It records how an observed fact may be obtained and how it must be preserved before the matrix, an issue or a test may change.

[REA (Reverse Engineer Anything)](https://github.com/morluto/rea) is an MIT-licensed CLI and MCP server for binary, JavaScript/Electron, `.NET`, Android and website analysis. It is an external developer tool. StageKeys does not vendor it, link it, or ship it, and the app's import path never calls it.

## Why it is useful here

StageKeys reads the channel-strip container structurally (`OCuA`/`UCuA` records, `GAME`/`MELC` device signatures, `MELCPMAS1MAS` sampler records, mapping markers) in [Sources/MainStagePatch.swift](../Sources/MainStagePatch.swift), and [Sources/MainStageProcessing.swift](../Sources/MainStageProcessing.swift) already translates a bounded set of processors from their `GAMETSPP` parameter records. So the remaining work is not "decode `.cst`"; it is the specific records whose field order, units or routing are still unknown.

| Input | Today | Remaining gap |
| --- | --- | --- |
| Channel EQ, Gain, Compressor, Stereo Delay, SilverVerb, Clip Distortion, Chorus | Translated, each with its own limitation note | DSP and taper fidelity, tracked in [#10](https://github.com/WorshipWarehouse/StageKeys/issues/10) |
| Any other processor in a `UCuA` record | Archived, blocker text, no substitute inserted | Parameter order, units and bypass encoding unknown, tracked in [#6](https://github.com/WorshipWarehouse/StageKeys/issues/6) |
| Saved Audio Unit (`PSDD`) | Reported as a device with its saved type/subtype, preset name, program count and state size, named in the channel blocker and in translation issues | Plug-in state is retained, not applied, and the saved version may differ from an installed one, tracked in [#6](https://github.com/WorshipWarehouse/StageKeys/issues/6) |
| Smart Control rows | Translated only when range mode is 0, `low<high`, and the saved value matches native units; otherwise archived | Other mapping modes and inactive-mix targets, tracked in [#6](https://github.com/WorshipWarehouse/StageKeys/issues/6) |
| `Channel_sends` | Detected and reported, never routed | Aux/bus topology, tracked in [#6](https://github.com/WorshipWarehouse/StageKeys/issues/6) |
| `MIDITransform` | Presence recorded as `hasMIDIState` | Not translated at all, tracked in [#6](https://github.com/WorshipWarehouse/StageKeys/issues/6) |
| Sampler amplitude curve, note range, transpose, sustain, pan, mute | Read and applied | Velocity, sample selection and filter response, tracked in [#1](https://github.com/WorshipWarehouse/StageKeys/issues/1) |
| ES2, Retro Synth, Sculpture, Alchemy | Archive only, explicit blocker | No native engine, tracked in [#7](https://github.com/WorshipWarehouse/StageKeys/issues/7) |
| MIDI scripts | Never executed | By design; not a gap to close |

One preflight question is now answered from the local library rather than left open. `MainStagePatch.devices` accepted only `GAME` and `MELC` and silently skipped a `UCuA` record with any other signature. Scanning 186 channel strips found 53 records with signature `PSDD`, all named `OB-Xd`, whose eight following bytes decode little-endian as `aumu`/`Obxd` — a saved Audio Unit component identity. Each record also wraps a plug-in-state plist whose own identity (`aumu`/`Obxd`/`DDSP`) confirms that reading and whose vendor payload is OB-Xd's XML bank of 128 programs; the importer reports that preset name, program count and state size without applying it. The installed plug-in reports `aumu Obx3 DDSP`, a newer subtype, so the saved record is also the only warning that an exact version is needed. `PSDD` records are now reported as devices with their saved identity and named in the channel blockers for [#5](https://github.com/WorshipWarehouse/StageKeys/issues/5); a synthetic fixture covers both the accepted record and the rejection of an arbitrary signature.

Meaning for the translated processors came from the parameter order in their records. Extending that to another processor means establishing the same three things for its record. That is the layer REA is for: it reports evidence with limitations instead of a confident guess, which matches the rules in [AGENTS.md](../AGENTS.md).

## Boundaries

Same limits as the rest of the project, plus REA's own disclaimer:

- Interoperability analysis of a locally authorized installation only. No decryption, no entitlement or trial circumvention, no extraction of protected vendor content, no copying of Apple, Sunday Sounds or third-party code, audio or art into this repository.
- Analysis targets (`.cst`, `.patch`, `MainStage.app`, sample libraries) stay outside version control; `*.cst`, `*.patch/` and audio files are already ignored.
- An observed symbol, class name, offset or string is a fact about the binary. It is not a license to reimplement by copying, and it is not proof of sound. Descriptions and measurements may be recorded; bytes and decompiled source may not ship.
- A result is reviewable only with the target identity (SHA-256), the tool and version, the exact command, and the platform it ran on.

## Verified capability

Recorded 2026-10-26 on the Linux analysis host (Ubuntu 24.04, Node 24.21.0), REA `rea-agents@6.8.0` via `npx`:

| Probe | Result | Use |
| --- | --- | --- |
| CLI start-up, `--help`, `doctor` | Works | `doctor` reports overall `healthy: false`: no analysis engine found, plus a Node patch-level warning |
| `inspect-byte-entropy <file>` | Works on an opaque `.cst`-style container; returns digest-bound Evidence | Locates structured versus compressed regions without knowing the format |
| `inspect-artifact <file>` | Rejects an unrecognized container (`unsupported_target`, `file_format_rejected`) | Confirms REA will not decode `.cst` for us; use it for Mach-O, app bundles and supported package formats |
| `inspect-keyed-archive <plist>` | Documented to read XML/binary Foundation keyed archives without instantiating classes | Wrong tool for `.cst`; relevant to MainStage resources and Apple containers |
| Hopper / Ghidra / IDA engines | Absent on this host | Required for `xrefs`, `function`, `decompile`, `search` inside Mach-O |

Consequences worth stating plainly:

- There is no automatic `.cst` decoder in REA and none is expected. Field meaning still has to be derived from MainStage's code, then proven with fixtures and renders.
- Deep native analysis needs an analysis engine (Hopper, Ghidra or IDA, licensed by the caller), and a live MainStage installation needs a macOS host. On this Linux host, without an engine, only the format-agnostic probes run.
- REA requires Node `^22.23.4 || ^24.22.1 || >=26.12.1`; this host is below that on 24.21.0 and npm prints `EBADENGINE` while the CLI still runs. Pin the version rather than tracking `latest`.

## The workflow

Artifacts and records live in a private workspace, by default `Analysis/` at the repository root, which is gitignored. `Tools/rea_probe.py` refuses to record an artifact from anywhere else inside the repository.

1. Capture the provenance of what is being examined: application, version, licence state, and who authorized the analysis.

   ```sh
   python3 Tools/rea_probe.py probe /path/to/Felt\ Piano.cst \
     --out Analysis/evidence \
     --application "Sunday Keys 2.5.2 (MainStage)" \
     --application-version 2.5.2 \
     --license-scope "Demo Mode" \
     --authorization "user-owned local installation; interoperability review" \
     --question "Which record keys encode the channel-strip output level?" \
     --rea-command "npx -y rea-agents@6.8.0"
   ```

   The record holds a SHA-256 of the artifact, leading-byte observations, bounded marker hits for the container literals, any REA Evidence captured to side files, and the host it ran on. It never writes to the artifact, instantiates archived classes or launches MainStage.

2. Add inferences only with cited observations. `verify` rejects an inference that cites nothing, a record without provenance, a malformed digest, and a record whose artifact sits in the repository.

   ```sh
   python3 Tools/rea_probe.py verify Analysis/evidence/*.evidence.json
   ```

3. For deep analysis on macOS, run the engine-backed probes against MainStage itself rather than the patch:

   ```sh
   npx -y rea-agents@6.8.0 setup      # registers the MCP server and workflow instructions, with backups
   npx -y rea-agents@6.8.0 doctor     # confirm the selected engine is found
   npx -y rea-agents@6.8.0 inspect-desktop-application "/Applications/MainStage 3.app" \
     --detail summary --evidence_output Analysis/evidence/mainstage-desktop.json
   npx -y rea-agents@6.8.0 search "/Applications/MainStage 3.app" MELCPMAS1MAS
   ```

   From a matched string, follow it to code with `xrefs <path> <address>`, read one routine with `function <path> <address>`, and read one path as pseudo-code with `decompile <path> --procedure <address>`. `demangle-swift` resolves Swift symbol names without an engine, and `inspect-keyed-archive <plist>` reads a Foundation keyed archive without instantiating classes.

   Save each command's Evidence JSON next to the record and reference it. `setup` edits agent configuration; review its diff before accepting it.

4. Summarize into the repository. Observations, method, host and limitations may be described in `Docs/` and `Docs/Calibrations/` with hashes and reproduction steps. Artifacts, raw dumps and decompiled output stay in `Analysis/`.

## Open issues this is meant to inform

Mapped to the existing index in [RELEASE-ISSUES.md](RELEASE-ISSUES.md); this plan opens no new scope and closes nothing.

| Issue | Probe | What would count as evidence |
| --- | --- | --- |
| [#6](https://github.com/WorshipWarehouse/StageKeys/issues/6) channel routing, effects, macros and MIDI | Literal search for `GAMETSPP`, `UCuA`, `MELCPMAS1MAS`, `MAPlugInParameterMapping` in MainStage binaries; then xrefs, function and decompile with an engine to recover one processor's parameter order, units and bypass flag | A field order that predicts a second patch's values without per-patch tuning, reproduced on two artifacts, then a synthetic fixture and a passing test |
| [#6](https://github.com/WorshipWarehouse/StageKeys/issues/6) `Channel_sends` and `MIDITransform` | Decompile the send/MIDI record writer once the container path is known | A decoded example whose native result matches a hand-configured equivalent |
| [#5](https://github.com/WorshipWarehouse/StageKeys/issues/5) preflight and missing content | `Tools/rea_probe.py` inventories, digests and marker scans over a selected folder | A reproducible inventory with hashes; absence of a literal is not proof of absence |
| [#7](https://github.com/WorshipWarehouse/StageKeys/issues/7) EXS coverage | `inspect-artifact` on the `.exs`, `inspect-keyed-archive` where the payload is a keyed archive | A field map that explains a specific rejected variant and passes the EXS tests |
| [#10](https://github.com/WorshipWarehouse/StageKeys/issues/10) effect matching | Only to confirm a parameter's identity and units; the matching itself is audio measurement | Not REA evidence: needs renders against a retained reference, per that issue's own criteria |
| [#13](https://github.com/WorshipWarehouse/StageKeys/issues/13), [#15](https://github.com/WorshipWarehouse/StageKeys/issues/15) hosted plug-ins and MIDI routing | Not an REA target | Those need device and plug-in testing, not binary analysis |
| [#21](https://github.com/WorshipWarehouse/StageKeys/issues/21) provenance | None | Analysis does not grant redistribution rights; the existing provenance rules still govern |

No row here authorizes a compatibility claim. A matrix change still needs, in order: an observation recorded with its target identity, a synthetic or user-authorized fixture, a test that fails before and passes after, and an audio or behavioural comparison where sound is at stake.

## What this does not establish

- No native MainStage patch playback, no private synth engine and no complete effect, routing, macro or MIDI parity.
- No claim that a MainStage version behaves as documented here; every observation is tied to a version and a hash.
- No claim that REA's output is correct. It reports what it observed, and its own disclaimer says results may be incomplete or wrong. Review the Evidence before relying on it.
- A recognised Audio Unit identity is not translated plug-in state. Nothing loads the AU, no saved state is applied, and the saved subtype may be older than the installed component.

If REA is ever vendored rather than run externally, add its MIT notice to `Licenses/` before distribution. Its third-party dependencies keep their own terms.
