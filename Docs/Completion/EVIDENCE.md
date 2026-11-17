# Evidence and execution ledger

Audit date: 2 November 2026. Source SHA `6a253130196e8beca471a575a45c1834d52cedf8`; remote main returned the same SHA. Host: macOS 27.2 (26B123), arm64, Xcode 27.2 (27B52), Node 26.4.0. No source/test changes were made. Build/test data stayed in /private/tmp with isolated per-test STAGEKEYS_DATA_DIR. Tests exercised generated samples; no installed user session or vendor payload was copied into this package.

## Executed commands/results

| Command | Result | Practical scope |
| --- | --- | --- |
| `python3 Tests/run-local-library.py . /private/tmp/stagekeys-completion-library` | environment-failure (exit 1) | Core compiled; first program passed; PersonalSoundPackTests aborted under sandbox Apple audio/service restrictions. Not a product-fix claim; unchanged sources rerun below. |
| `python3 Tests/run-local-library.py . /private/tmp/stagekeys-completion-library-unrestricted` | passed-with-skips (exit 0) | Normal Apple service access; disposable STAGEKEYS_DATA_DIR per program. 99 entries: 88 passed, 11 explicit private-fixture skips, 0 failed. |
| `Tools/verify-release.sh mac /private/tmp/stagekeys-completion-mac` | environment-failure (exit code not retained) | SwiftUI macro helper sandbox_apply Operation not permitted and cascading missing @State members; unchanged normal-service retry passed. |
| `Tools/verify-release.sh simulator /private/tmp/stagekeys-completion-simulator` | environment-failure (exit code not retained) | CoreSimulator/service and compiler helper restrictions; not mobile qualification. |
| `Tools/verify-release.sh mac /private/tmp/stagekeys-completion-mac-unrestricted` | passed (exit 0) | Unsigned universal arm64/x86_64 artifact; bundle/provenance/notices/personal-pack metadata gates passed. |
| `Tools/verify-release.sh simulator /private/tmp/stagekeys-completion-simulator-unrestricted` | passed (exit 0) | Unsigned simulator artifact/content/document/icon gates passed. CoreSimulator version mismatch warning remains; no simulator app interaction or physical-device run. |
| `Tests/test-reverb.sh` | passed (exit 0) | 21 C test programs under AddressSanitizer and UndefinedBehaviorSanitizer; tested code assertions at declared sample rates, not audible reference fidelity. |
| `python3 Tests/test-*.py (each of the 9 files, individually)` | passed (exit 0) | All nine Python script entry points returned 0; exact command/exit pairs are in the log. |

Normal-service retries used the execution tool’s reviewed escalation, not changed application code or disabled build gates. Initial failures remain visible. Full commands, local log paths and SHA-256 digests are in verification.json; raw build logs are temporary and may be removed by OS cleanup. Preserve them externally if long-term audit retention is needed. Machine-readable per-program results are retained in this package.

The nine Python programs: test-app-icon.py, test-audit-mainstage-presets.py, test-catalog-tags.py, test-distribution.py, test-library-gate.py, test-local-library-runner.py, test-pack-document-type.py, test-preset-coverage.py, test-sampler-calibration.py. No separate linter was configured. `git diff --check` and local Markdown link/inventory checks validate the final documentation.

## Explicit skipped tests

These 11 entries were skipped, not exercised compatibility passes:
- `PianoFidelityTests`: SKIP: private piano fixture unset
- `EXSAmplitudeUpgradeTests`: SKIP: private sampler/source unset
- `EXSResponseUpgradeTests`: SKIP: private response fixture unset
- `EXSVoiceUpgradeTests`: SKIP: private v2 sampler/source fixture unset
- `EXSImportTests`: SKIP EXS test: provide scratch directory, installed EXS, and explicit sample root
- `ModernEXSImportTests`: SKIP: provide private EXS fixture and selected sample root
- `ModernEXSPlaybackTests`: SKIP: provide private EXS fixture and selected sample root
- `MainStageAutoConversionTests`: SKIP: private bundled MainStage fixture unset
- `MainStagePackTests`: SKIP: private MainStage pack unset
- `ReferencedMainStageImportTests`: SKIP: provide private source patch and selected sample root
- `ImportedAttackAuditTests`: SKIP: optional installed-sound audit fixture unset

Other limitations: PianoHeldNoteTests is default-gated but returns early without STAGEKEYS_PIANO_PRESET and does not emit SKIP; therefore its runner status `passed` does not establish private held-piano coverage. Generated tests in other programs still exercise held notes. Runner summaries are program outcomes, not a count of every fully exercised branch. On-demand tests from LOCAL-VERIFICATION were not all run. N06 proposes the focused reporting repair; current recorded totals remain the actual runner output.

## GitHub read evidence

The GitHub connector was absent. Read-only gh fallback succeeded with network access after the initial sandbox network failure:

```sh
gh issue list --repo WorshipWarehouse/StageKeys --state all --limit 1000 --json number,title,state,body,comments,labels,milestone,url,createdAt,updatedAt,closedAt
gh pr list --repo WorshipWarehouse/StageKeys --state all --limit 1000 --json number,title,state,body,url,mergedAt,headRefOid
gh api repos/WorshipWarehouse/StageKeys/labels --paginate
gh api repos/WorshipWarehouse/StageKeys/milestones --paginate
gh api repos/WorshipWarehouse/StageKeys/commits/main --jq .sha
gh run list --repo WorshipWarehouse/StageKeys --limit 8 --json databaseId,headSha,status,conclusion,displayTitle
```

51 issues: 35 OPEN, 16 CLOSED; 75 PRs, none OPEN in snapshot. All issue bodies/discussions read; relevant current PR descriptions and prior PR-HISTORY-AUDIT inspected. No complete new historical PR diff/review-thread review is claimed. The latest main workflow snapshot [run 41220745067](https://github.com/WorshipWarehouse/StageKeys/actions/runs/41220745067) reported completed/success at the audited SHA. This is a read result, not a freshly triggered hosted run. Labels were default plus accessibility; no milestones returned. github-inventory.json retains item identities, state, body/discussion digests and recent run metadata; raw issue discussions remain in /private/tmp/stagekeys-audit-issues.json and live GitHub.

## Reference static evidence and tool limitations

- Ordinary plist reads: Sunday Keys 2.5.2 (3367); MainStage 4.3.1 (5233). These verify installed metadata only.
- CUA native app lookup timed out -10005. No screen capture or runtime behavior verified.
- `npx --no-install rea-agents doctor --client codex --json` attempted registry resolution and failed ENOTFOUND; no install/config repair followed. Located existing cached official launcher at `/Users/calebhines/.npm/_npx/9b9809298fe40d2c/node_modules/.bin/rea` (6.7.0).
- Installed CLI doctor under sandbox failed compiling its process-ownership helper because normal cache writes were denied. Normal-service retry completed the report with unhealthy/config_drift status: Codex registration stale, Hopper present, Ghidra/IDA unavailable. No REA setup or global changes made.
- `inspect-desktop-application --help` returned the global command catalog; that operation is not advertised in 6.7.0. Used its actual supported `inspect-macho` instead.
- `rea inspect-macho "/Applications/Sunday Keys.app/Contents/MacOS/Sunday Keys" --format json` initially failed in helper compilation; unchanged normal-service retry exited 0 and returned complete REA Evidence.

Target SHA-256: `501f35cc48b4d897b76875faca6b0f8b4b1477a686bd4409476e40fef3288c86`. Evidence ID `ev_95b7ab92f4046760aa7e0b9f07b34a335ab7134d11220b2c03655a5e8d8b43b6`. Native-macos provider selected arm64 from universal x86_64/arm64; UUID `D46737DB-2A2B-3A60-B351-14B60D235669`. This establishes executable inventory/identity, not behavior, source recovery or authorization to copy vendor assets. The summary is in [reference-static-summary.json](reference-static-summary.json); complete raw symbol/metadata evidence remains outside the repository at the digest-bound location in verification.json.

REA limitations: Imports and exports combine dyld_info and nm; stripped or toolchain-hidden symbols may be absent.; vtool output is retained as provenance but only otool build metadata is normalized..

First-party manual pages consulted 2 November: [Patch Snapshots](https://support.sundaysounds.com/article/3139-patch-snapshots) (page states last updated 23 April 2024), [Settings](https://support.sundaysounds.com/article/3194-settings), [Sounds](https://support.sundaysounds.com/article/3141-sounds), and [REA upstream](https://github.com/morluto/rea). Manuals are DOCUMENTED reference evidence, not a verified interaction with the installed binary. No proprietary screenshots/audio/payloads were copied.

## Code anchors for material findings

| Finding | Audited source / symbol | Evidence class |
| --- | --- | --- |
| Recorder locks/allocates on tap path | Sources/AudioController.swift installOutputTap; Sources/AudioDiagnosticRecorder.swift append | VERIFIED source; latency impact UNKNOWN |
| Click bypasses main limiter | Sources/AudioController.swift init connects metronomeNode directly to protectedOutput | VERIFIED topology; overload UNKNOWN |
| Graph transaction lacks general rollback | Sources/ExternalInstruments.swift editGraph/finishGraphChanges | VERIFIED structure; specific -1 cause UNKNOWN |
| Snapshot extended state | Sources/Models.swift SnapshotSoundState; Sources/Store.swift recall | VERIFIED source; product choice pending |
| Primary/Secondary share note/CC handling | Sources/Store.swift handleMIDI OR accepts guard before message switch | VERIFIED source; differs from #15 manual-derived Primary-only requirement |
| Fixed MIDI learn target coverage incomplete | Sources/MIDIControlTarget.swift enum; Store.applyMIDIControl | VERIFIED source; no tonic brightness/shimmer/effect-parameter targets |
| Pitch bend has no Store dispatch case | Sources/Store.swift handleMIDI switch has note/CC/PC only, default breaks | VERIFIED source; not evidence all reference bend semantics known |
| Imported processing order differs from C path | ExternalInstruments voice connections and connectEffects vs Synth.c render | VERIFIED code distinction; source-intent validation needed |
| Background policy missing | StageKeysApp scenePhase, Store AVAudioSession interruption handler | VERIFIED source; physical result UNKNOWN |
| Root project license unspecified | README/AGENTS and no root LICENSE; closed #64 has no decision comment | VERIFIED repository/issue fact; owner decision needed |

## Remaining unexamined work

See the explicit scope/continuation sections of 01 and 02. Runtime reference interactions, matched source listening/calibrations, physical mobile/MIDI/audio rigs, long soak, all on-demand private/third-party tests, every historical PR review/diff and separate private library issues remain unverified. The plan is complete as a reviewable research package; qualification itself is deliberately unfinished.
