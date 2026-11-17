# PR history audit

Reviewed 50 StageKeys PRs: 18 closed without a GitHub merge label, 25 merged and seven open at the snapshot. The two Live PRs were merged. Collected every PR diff and changed-file inventory; audited closed-PR ancestry and closure records, reviewed later changes and selected high-risk source paths. This is not a claim of line-by-line revalidation of every historical implementation. This is a source/history audit with focused regressions, not complete third-party/plugin/hardware or proprietary sonic-parity qualification.

## Closed does not mean discarded

All 18 closed PRs have their original feature commits in integration head `074dedd`. That head and its landed squash `62dd46b` have the identical tree `88b333e9399a461f370569e7af1a57c5fe2b0b35`. Subsequent commits outside that ancestry are merge-main bookkeeping, lipo/script-mode fixes and one observer-dispatch variant. Current main has corrected lipo arguments/executable script and main-queue observer dispatch with generation checking; #66 improves its regression timing. No missing original feature commit was found.

Do not reopen #34, #36, #38–#49, #51, #57, #59 or #61 just to obtain a merged badge. Their features already landed. Merge conflicts now arise from later fixes and duplicate history; blindly remerging those branches can undo newer checks or source changes. The original #62 description incorrectly predicted preserved ancestry after landing; the squash tree equality, rather than the GitHub badge or description, is the content evidence.

## Keep and harden

- Keep #26/#27/#29 and #62: sampler, AU/MIDI and integration fixes have focused regression evidence, with physical/device/source limits remaining in release issues.
- Keep #30 and incorporated #47/#48 automation smoothing. The independently found float ClipDist convergence floor is addressed by pending #84; reverting smoothing would restore abrupt parameter steps.
- Keep #63’s eligible Tonic picker; it does not close the wider #54 AU-pad/audition lifecycle gate.
- Keep #67/#70 saved-AU import, but correct matching: an exact component triple must survive a renamed display label, and multiple name-only subtype candidates must not silently select the first. This follow-up adds both-order ambiguity, exact-precedence and renamed-identity tests while retaining saved-state preservation.
- Keep #66’s bounded condition wait and stale-observer assertions, #69’s single-run CI triggers, and #71/#73–#75/#78 evidence/content/tag/refusal hardening.
- Keep #80 and Live #2: pre-load residency fixes measured sustained-sample gaps; preserve original samples and retain repeatable gain/continuity gates.
- Keep Live #1’s scoped channels/snapshot/metronome changes. It has focused Live tests; complete mobile/UI/source parity remains unverified.

## Pending review

#76 and #77 are already incorporated in pending integration #81. Once that lands, close the originals as superseded rather than reapply them. #83, #84, #86 and #90 are focused follow-ups with local evidence and hosted checks; their shared test-list edits must be reconciled against #81 without dropping any test. Retain branch protections. This audit does not authorize merging a failing or stale revision.

No PR is labelled “bad” merely for being closed. No wholesale revert is justified by the evidence inspected; concrete defects receive targeted fixes. Do not treat this conclusion as complete feature acceptance or a listening comparison.

## Per-PR decisions

| PR | State at audit | Decision |
| --- | --- | --- |
| [#26](https://github.com/WorshipWarehouse/StageKeys/pull/26) | MERGED | Keep; no full-PR revert justified by this audit |
| [#27](https://github.com/WorshipWarehouse/StageKeys/pull/27) | MERGED | Keep; no full-PR revert justified by this audit |
| [#29](https://github.com/WorshipWarehouse/StageKeys/pull/29) | MERGED | Keep; no full-PR revert justified by this audit |
| [#30](https://github.com/WorshipWarehouse/StageKeys/pull/30) | MERGED | Keep; no full-PR revert justified by this audit |
| [#31](https://github.com/WorshipWarehouse/StageKeys/pull/31) | MERGED | Keep; no full-PR revert justified by this audit |
| [#32](https://github.com/WorshipWarehouse/StageKeys/pull/32) | MERGED | Keep; no full-PR revert justified by this audit |
| [#33](https://github.com/WorshipWarehouse/StageKeys/pull/33) | MERGED | Keep; no full-PR revert justified by this audit |
| [#34](https://github.com/WorshipWarehouse/StageKeys/pull/34) | CLOSED | Keep closed: original features included via #62; no missing feature commit found |
| [#35](https://github.com/WorshipWarehouse/StageKeys/pull/35) | MERGED | Keep; no full-PR revert justified by this audit |
| [#36](https://github.com/WorshipWarehouse/StageKeys/pull/36) | CLOSED | Keep closed: original features included via #62; no missing feature commit found |
| [#37](https://github.com/WorshipWarehouse/StageKeys/pull/37) | MERGED | Keep; no full-PR revert justified by this audit |
| [#38](https://github.com/WorshipWarehouse/StageKeys/pull/38) | CLOSED | Keep closed: original features included via #62; no missing feature commit found |
| [#39](https://github.com/WorshipWarehouse/StageKeys/pull/39) | CLOSED | Keep closed: original features included via #62; no missing feature commit found |
| [#40](https://github.com/WorshipWarehouse/StageKeys/pull/40) | CLOSED | Keep closed: original features included via #62; no missing feature commit found |
| [#41](https://github.com/WorshipWarehouse/StageKeys/pull/41) | CLOSED | Keep closed: original features included via #62; no missing feature commit found |
| [#42](https://github.com/WorshipWarehouse/StageKeys/pull/42) | CLOSED | Keep closed: original features included via #62; no missing feature commit found |
| [#43](https://github.com/WorshipWarehouse/StageKeys/pull/43) | CLOSED | Keep closed: original features included via #62; no missing feature commit found |
| [#44](https://github.com/WorshipWarehouse/StageKeys/pull/44) | CLOSED | Keep closed: original features included via #62; no missing feature commit found |
| [#45](https://github.com/WorshipWarehouse/StageKeys/pull/45) | CLOSED | Keep closed: original features included via #62; no missing feature commit found |
| [#46](https://github.com/WorshipWarehouse/StageKeys/pull/46) | CLOSED | Keep closed: original features included via #62; no missing feature commit found |
| [#47](https://github.com/WorshipWarehouse/StageKeys/pull/47) | CLOSED | Keep closed: original features included via #62; no missing feature commit found |
| [#48](https://github.com/WorshipWarehouse/StageKeys/pull/48) | CLOSED | Keep closed: original features included via #62; no missing feature commit found |
| [#49](https://github.com/WorshipWarehouse/StageKeys/pull/49) | CLOSED | Keep closed: original features included via #62; no missing feature commit found |
| [#50](https://github.com/WorshipWarehouse/StageKeys/pull/50) | MERGED | Keep; no full-PR revert justified by this audit |
| [#51](https://github.com/WorshipWarehouse/StageKeys/pull/51) | CLOSED | Keep closed: original features included via #62; no missing feature commit found |
| [#57](https://github.com/WorshipWarehouse/StageKeys/pull/57) | CLOSED | Keep closed: original features included via #62; no missing feature commit found |
| [#59](https://github.com/WorshipWarehouse/StageKeys/pull/59) | CLOSED | Keep closed: original features included via #62; no missing feature commit found |
| [#61](https://github.com/WorshipWarehouse/StageKeys/pull/61) | CLOSED | Keep closed: original features included via #62; no missing feature commit found |
| [#62](https://github.com/WorshipWarehouse/StageKeys/pull/62) | MERGED | Keep integration; verified head tree equals squash tree |
| [#63](https://github.com/WorshipWarehouse/StageKeys/pull/63) | MERGED | Keep scoped picker; #54 still tracks remaining pad lifecycle/workflows |
| [#65](https://github.com/WorshipWarehouse/StageKeys/pull/65) | MERGED | Keep; no full-PR revert justified by this audit |
| [#66](https://github.com/WorshipWarehouse/StageKeys/pull/66) | MERGED | Keep; no full-PR revert justified by this audit |
| [#67](https://github.com/WorshipWarehouse/StageKeys/pull/67) | MERGED | Keep hosted-AU work; harden ambiguous/renamed component matching in this follow-up |
| [#68](https://github.com/WorshipWarehouse/StageKeys/pull/68) | MERGED | Keep; no full-PR revert justified by this audit |
| [#69](https://github.com/WorshipWarehouse/StageKeys/pull/69) | MERGED | Keep; no full-PR revert justified by this audit |
| [#70](https://github.com/WorshipWarehouse/StageKeys/pull/70) | MERGED | Keep hosted-AU work; harden ambiguous/renamed component matching in this follow-up |
| [#71](https://github.com/WorshipWarehouse/StageKeys/pull/71) | MERGED | Keep; no full-PR revert justified by this audit |
| [#72](https://github.com/WorshipWarehouse/StageKeys/pull/72) | MERGED | Keep; no full-PR revert justified by this audit |
| [#73](https://github.com/WorshipWarehouse/StageKeys/pull/73) | MERGED | Keep; no full-PR revert justified by this audit |
| [#74](https://github.com/WorshipWarehouse/StageKeys/pull/74) | MERGED | Keep; no full-PR revert justified by this audit |
| [#75](https://github.com/WorshipWarehouse/StageKeys/pull/75) | MERGED | Keep; no full-PR revert justified by this audit |
| [#76](https://github.com/WorshipWarehouse/StageKeys/pull/76) | OPEN | Already incorporated in pending #81; avoid duplicate merge after #81 lands |
| [#77](https://github.com/WorshipWarehouse/StageKeys/pull/77) | OPEN | Already incorporated in pending #81; avoid duplicate merge after #81 lands |
| [#78](https://github.com/WorshipWarehouse/StageKeys/pull/78) | MERGED | Keep; no full-PR revert justified by this audit |
| [#80](https://github.com/WorshipWarehouse/StageKeys/pull/80) | MERGED | Keep; no full-PR revert justified by this audit |
| [#81](https://github.com/WorshipWarehouse/StageKeys/pull/81) | OPEN | Retain for protected review; not an approval based solely on status |
| [#83](https://github.com/WorshipWarehouse/StageKeys/pull/83) | OPEN | Retain for protected review; not an approval based solely on status |
| [#84](https://github.com/WorshipWarehouse/StageKeys/pull/84) | OPEN | Retain for protected review; not an approval based solely on status |
| [#86](https://github.com/WorshipWarehouse/StageKeys/pull/86) | OPEN | Retain for protected review; not an approval based solely on status |
| [#90](https://github.com/WorshipWarehouse/StageKeys/pull/90) | OPEN | Retain for protected review; not an approval based solely on status |

Exact heads, changed files and exception commits are in `PR-HISTORY-AUDIT.json`. Local focus: MainStage parser/AU import/layer assembly, parameter observers, sampler startup, snapshots, setlist aliases and Store regression checks. Private sound fixtures, physical power-on, iPad execution, eight-hour soak and source listening were not newly performed.

## Follow-up verification

All eight focused tests completed successfully with synthetic/disposable data: MainStagePatchTests, MainStageAudioUnitImportTests, MainStageLayerAssemblyTests, PluginParameterModelTests, SamplerStartupTests, SnapshotSlotTests, SetlistPathAliasTests and StoreTests. The expanded MainStagePatchTests rejects the old compiled matcher at the renamed exact-identity assertion. No original sample payloads or user sessions were edited.
