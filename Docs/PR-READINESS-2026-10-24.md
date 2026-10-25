# PR readiness audit — 24 October 2026

This audit distinguishes a focused implementation from completion of its wider release issue. The 22 open PRs #30–#51 have no unresolved review threads in the fetched GitHub review-thread data. All were individually mergeable against the current main at inspection; that does not make the combined stack conflict-free. No blanket approval or completed hardware qualification is implied.

## Findings fixed

- PR #50: a 540-point minimum allowed complex editors/library headers to collapse and crop. Minimum dimensions now retain intended content size when the display has space, while remaining bounded on smaller displays.
- PR #31: distribution and sampler-calibration Python gates now run when their corresponding files enter the stack.
- PR #59 / issue #58: the broader StoreTests exposed valid saved setlists disappearing from inventory because macOS enumerates `/private/var` while the root normalizes to `/var`. Canonical parent comparison repairs visibility without accepting symlink files.
- PR #57 / issue #56: five snapshot positions, sparse capture, stable clearing and legacy recall are implemented and tested.

## Existing PR scope and issue coverage

| PR | Related issue | Implemented scope |
| --- | --- | --- |
| [#30](https://github.com/WorshipWarehouse/StageKeys/pull/30) | #11 | Smooth dense reverb Tone and Low Cut changes |
| [#31](https://github.com/WorshipWarehouse/StageKeys/pull/31) | #22 | Add release build and audio regression gates (#22) |
| [#32](https://github.com/WorshipWarehouse/StageKeys/pull/32) | #21 | Enforce distribution provenance and public signing gates (#21) |
| [#33](https://github.com/WorshipWarehouse/StageKeys/pull/33) | #20 | Prevent corrupt-session autosave loss and add recovery (#20) |
| [#34](https://github.com/WorshipWarehouse/StageKeys/pull/34) | #23 | Add private support diagnostics and beta setup guide (#23) |
| [#35](https://github.com/WorshipWarehouse/StageKeys/pull/35) | #25 | Report gain-match repeatability and make trims reversible (#25) |
| [#36](https://github.com/WorshipWarehouse/StageKeys/pull/36) | #5 | Review MainStage channels before converting sounds (#5) |
| [#37](https://github.com/WorshipWarehouse/StageKeys/pull/37) | #7 | Report unsupported MainStage engines and refuse guessed envelopes (#7) |
| [#38](https://github.com/WorshipWarehouse/StageKeys/pull/38) | #8 | Make bulk catalog imports cancellable and transactional (#8) |
| [#39](https://github.com/WorshipWarehouse/StageKeys/pull/39) | #13 | Bound plugin loading and block interrupted retries (#13) |
| [#40](https://github.com/WorshipWarehouse/StageKeys/pull/40) | #4 | Stress every effect and record worst render durations (#4) |
| [#41](https://github.com/WorshipWarehouse/StageKeys/pull/41) | #14 | Guard mobile AU editor lifecycle and define VST3 scope (#14) |
| [#42](https://github.com/WorshipWarehouse/StageKeys/pull/42) | #3 | Meter actual protected stereo output and expose overload (#3) |
| [#43](https://github.com/WorshipWarehouse/StageKeys/pull/43) | #17 | Fix false arp tags and make unknown metadata filterable (#17) |
| [#44](https://github.com/WorshipWarehouse/StageKeys/pull/44) | #1 | Require source-backed velocity and loudness evidence (#1) |
| [#45](https://github.com/WorshipWarehouse/StageKeys/pull/45) | #6 | Assemble converted channels while preserving processing (#6) |
| [#46](https://github.com/WorshipWarehouse/StageKeys/pull/46) | #18 | Keep mod-wheel drags synchronized with hardware CC1 (#18) |
| [#47](https://github.com/WorshipWarehouse/StageKeys/pull/47) | #9 | Smooth Shimmer mix and damping automation (#9) |
| [#48](https://github.com/WorshipWarehouse/StageKeys/pull/48) | #10 | Smooth imported ClipDist gain and mix automation (#10) |
| [#49](https://github.com/WorshipWarehouse/StageKeys/pull/49) | #16 | Guard sound edits and verify all 15 playback slots (#16) |
| [#50](https://github.com/WorshipWarehouse/StageKeys/pull/50) | #19 | Add keyboard audio controls and flexible editor sizing (#19) |
| [#51](https://github.com/WorshipWarehouse/StageKeys/pull/51) | #24 | Define validated local patch drafts for the later builder (#24) |

These PRs deliberately implement parts of broader release gates. The linked issues stay open until their full acceptance criteria are met, rather than being closed merely because a related PR exists. In particular: sampler/source listening and physical latency (#1/#2), hardware/long soak (#3/#4), complete native routing/import coverage (#5–#8), effects listening (#9–#11), AU automation/platform/topology qualification (#12–#14), external-device routing (#15), all-screen workflows (#16–#19), clean-device restore (#20), signing/rights (#21), functioning hosted CI (#22), beta support (#23), the later builder UI (#24) and broader instrument probes (#25) remain.

## Verification and merge constraints

- Previous frozen integration passed the complete library and DSP sanitizer suites; no audio DSP changed in this UI follow-up.
- New Mac universal and iOS Simulator integration builds passed with the snapshot/PR #50 changes. Final Mac rebuild also includes the path-only repair.
- New SnapshotSlotTests passes sparse capture, no empty recall, stable clearing, bounds and legacy/session round trips. SetlistPathAliasTests and the full StoreTests pass after the path fix.
- Affected integration suite passes snapshot slots, all 15 slots, recovery, plugin journal, final output metering, channel assembly, preflight, transactional import, AU catalog/state compatibility and MIDI setup.
- Live-specific metronome regression verifies old enabled requests cannot produce audio clicks and save as disabled.
- GitHub Actions #31 and the remaining red checks cannot be called green: the inspected build job has runner_id=0, no steps, and a billing/spending-limit annotation before startup. PR #30 currently reports SUCCESS. Restoring runner availability and successful checks is still required for CI-qualified merging.
- Merge the independent path repair before enabling StoreTests as a default gate. Retain every test when combining the repeatedly edited test-library.sh line. Native-import Store/SoundImportView changes, Synth EffectState fields, AudioDiagnosticRecorder additions and mobile/plugin-load guards also overlap. The local verify/all-release-issue-prs branch records tested resolutions; do not drop either side of those changes.
- Physical iPad execution, full third-party AU compatibility, source listening, measured hardware latency, signed distribution and eight-hour live soak were not performed in this audit.

## Added focused issues

- #52: choose MainStage source effects for visible slots; EQ/compression in instrument controls, no automatic overflow racks.
- #53: automatic AU editor presentation after add, expand/collapse and lifecycle.
- #54: user-library Tonic Pad selection with eligibility and AU lifecycle qualification.
- #55: bounded detached reverb tails across instrument/graph changes.
- #56: five stable snapshot positions (PR #57).
- #58: saved-setlist path aliases (PR #59).

PRs #57 and #59 use Closes links, so their narrow issues close on merge. No broad release issue is marked complete prematurely.

## Live startup blocker found after local builds

The real multi-instrument Piano session did not become responsive within several minutes. A one-second process sample traced the main thread to `PerformanceStore.start → applyPatch → AudioController.configure → editGraph → restoreSamplers → AVAudioUnitSampler.loadInstrument`; the process used about 2 GB resident memory. Issue #60 records the investigation and acceptance criteria. The development StageKeys process was stopped and the previous app bundle restored; no session/library/sample files were reset. StageKeys Live's instrument-channel update remains installed. This finding blocks a blanket merge-ready statement for the full stack despite successful local builds/offline regressions. The individual snapshot and path corrections remain available in PRs #57/#59.
