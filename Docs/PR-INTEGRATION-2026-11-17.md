# Reviewed PR integration — 17 November 2026

The owner authorized review, fixes and merging. Baseline `c9d7152` already contains
Nord PR #225. Its completed bounded-reader issue #211 was closed with evidence;
superseded readers #218/#223 were retired. This integration retains the following
reviewed PR commits and reconciles their overlapping changes.

| PR | Reviewed head | Scope |
| --- | --- | --- |
| [#198](https://github.com/WorshipWarehouse/StageKeys/pull/198) | `1e56c44d85eb` | Research/sunday effect parity |
| [#201](https://github.com/WorshipWarehouse/StageKeys/pull/201) | `d656ee5444e9` | Add versioned Stage Clip Distortion core |
| [#202](https://github.com/WorshipWarehouse/StageKeys/pull/202) | `951220edce85` | Add Stage Pitch shifter core |
| [#203](https://github.com/WorshipWarehouse/StageKeys/pull/203) | `966ce09517f9` | Add Stage Shimmer core |
| [#204](https://github.com/WorshipWarehouse/StageKeys/pull/204) | `3f995c7973cf` | [codex] Extend scheduler clock boundary regressions |
| [#205](https://github.com/WorshipWarehouse/StageKeys/pull/205) | `a17b8c3493b5` | [codex] Add offline stereo render budget reporting |
| [#207](https://github.com/WorshipWarehouse/StageKeys/pull/207) | `f0813aa8666e` | [codebuff] Keep a recoverable previous copy of saved setlist documents |
| [#208](https://github.com/WorshipWarehouse/StageKeys/pull/208) | `52c85d95b7e2` | Move EXS source zones with instrument transpose (#7) |
| [#209](https://github.com/WorshipWarehouse/StageKeys/pull/209) | `4b1a42e28b0a` | Report detected stereo output pairs for the selected device (#107) |
| [#210](https://github.com/WorshipWarehouse/StageKeys/pull/210) | `e6bc022bc911` | Add a recoverable way to remove an imported sound from My Sounds |
| [#217](https://github.com/WorshipWarehouse/StageKeys/pull/217) | `375019784ed2` | Size the library rating stars' tappable box from the audited hit-target minimum |
| [#219](https://github.com/WorshipWarehouse/StageKeys/pull/219) | `a8d81224ecc3` | Size the workspace strip's performer buttons from the audited hit-target minimum |
| [#220](https://github.com/WorshipWarehouse/StageKeys/pull/220) | `38ce62d2ffe9` | Size the dense performer controls from the audited touch minimum |
| [#221](https://github.com/WorshipWarehouse/StageKeys/pull/221) | `d1066425fc1d` | Date MIDI clock pulses with the CoreMIDI packet stamp |
| [#222](https://github.com/WorshipWarehouse/StageKeys/pull/222) | `a15ed704bad5` | Add personal sound favorites as a library filter (#17) |
| [#224](https://github.com/WorshipWarehouse/StageKeys/pull/224) | `0abd3f21ecce` | Repair a library sound whose sample folder moved (#17) |

## Review findings resolved

- Preserve every CoreMIDI packet timestamp through a new timed callback; retain the untimed C ABI. Direct C lists and a virtual CoreMIDI source test two distinct clock packets in one list. Zero/invalid-stamp receipt fallback remains.
- Retain the exact named removal/Undo state after a failed Undo or a subsequent failed removal. The same tested feedback model drives the browser.
- Keep sound names full-width on iOS by placing favorite/rating actions below them. Favorites receive an audited target. Workspace targets include the complete styled footprint, without adding style padding again. Physical layout/accessibility qualification remains separate.
- Report odd leftover hardware channels, refuse stale device ID/name substitution and preserve unknown iOS channel counts instead of inventing stereo. This adds no multi-output routing.
- Admit recovered setlists before publication (retained upstream fix), and force staged Audio Unit re-instantiation for active recovery even when cached state matches. A nil authored state receives a fresh default instance. Offline recovery invalidates caches without loading units. A generated-unit regression verifies saved state wins over editor-mutated live state.
- Make Stage Shimmer Low Cut/Tone automation reach the running tank. The new regression fails against the old core and passes with the fix. Replace the flanger first-sample-only check with multi-sample fade/engagement evidence.
- Keep omitted legacy Chorus parameters at their old defaults; new Stage factory presets retain explicit new defaults. Require exact generated-effect equality before migrating the Felt Room profile, preserving disabled/edited effects.
- Validate repaired sampler structure and audio headers before publishing a successful repair; corrupt matching-name audio is rejected and unique new assets are rolled back. Replace the previous fake-RIFF success fixture with real generated PCM.
- Bundle and enforce DaisySP/Signalsmith notices on both app targets. Reject personal favorites metadata as a distribution asset. No vendor/user audio, session or plug-in state is committed.

## Validation

- Complete combined library gate: **136 passed, 12 explicit private-fixture skips, 0 failed**. The optional private PianoHeldNote fixture remains unexercised despite its program passing.
- Final focused checks after the repair-header and named-route refinements: **6 passed, 0 skipped, 0 failed** (`LibraryRepairTests`, `AudioDeviceInventoryTests`, `EffectPresetTests`, `SoundLibraryTests`, `SetlistRecoveryStateTests`, `MIDIInputTests`).
- Complete 31-program DSP AddressSanitizer/UndefinedBehaviorSanitizer suite passed; the final legacy-Chorus default adjustment also passed `StageChorusTests` under both sanitizers.
- Universal unsigned Mac and iOS Simulator artifact gates passed on the combined changes; final-commit build/CI outcomes are attached to the integration PR. These are not signing/install or physical-device results.
- Test registration (138 Swift / 10 C / 31 sanitizer programs), distribution refusal, accessibility-source audit and MIDI packet wiring checks passed.
- Existing per-PR CI results were inspected together with thread-aware review state and actual source. No branch protection bypass or administrator merge is used.

## Issue disposition

Only #211 has complete reviewed acceptance evidence from the Nord merge. Decoder pitch/reference evidence (#212), detailed native musical mapping/qualification (#213), the remaining visible/failure-path import criteria (#214), audible intended Mac rig qualification (#215) and physical iPad qualification (#216) remain open.

Broader #4/#7/#15/#17/#19/#20/#107/#108/#111 gates also remain open. Offline tools do not establish hardware performance; library features do not complete physical layouts/optional-library versioning; transpose fixes do not establish every EXS/instrument variant; recovery software does not prove clean-device restore. PR descriptions #205/#207 were corrected so GitHub cannot accidentally interpret their negated closure wording as completion of #4/#20.

Effects remain independent StageKeys implementations and bounded calibration profiles. No complete Sunday Keys, Nord, MainStage or proprietary DSP parity is asserted.
