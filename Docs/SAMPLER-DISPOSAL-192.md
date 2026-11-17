# Sampler disposal and safe restart — issue #192

This is a follow-up to PR #197 (`259663739bb740308731c8e5cb2e5b9880816313`), which supplies the stopped disposal order, ownership registry, rollback pruning and bounded local lifecycle ledger. Review/merge that prerequisite with this follow-up; the original private crash's CoreAudio assertion and instrument identity remain unknown. The original scenario is explicitly unreproduced.

## Defect and correction

The prerequisite recorded a detached sampler as `retainedPastStop` but cleared its pending record and still restarted. A second owner could therefore release that sampler after rendering resumed, the ordering the crash issue requires excluding. A generated regression that deliberately retains the retired sampler fails against unchanged #197 with “An externally retained disposed sampler must block forward and rollback restart.” This is a reproduction of the missing guard, not a reproduction of CoreAudio's original SIGTRAP.

Pending weak disposal references now exist in all builds. Forward completion, rollback completion, explicit Start and offline-start check them before restarting. A still-live detached sampler produces `StageKeysSamplerTeardown / 192`, keeps audio stopped and uses the existing graph-failure/manual-retry state. Recovery cannot clear a still-live pending disposal. Once the owner releases it while stopped, explicit Start can recover the authored patch. No polling retry, vendor cancellation or exception-catching workaround is introduced.

The broader AU-commit suite also exposed a real extra owner: AudioController's completion closure retained the previous unit, and the loader's already-finished timeout retained that closure. Its previous-unit identity observation is now weak, with an explicit prior-presence flag so a released unit cannot be misreported as a retained old sound. The weak success-path test observations and its release assertion exercise this production correction.

The weak check does not retain samplers. Diagnostic details remain DEBUG-only, bounded and local. The guard applies to tail samplers registered by the stopped truncation/purge path; it is not a general third-party AU lifetime or crash-containment guarantee. Other unsafe teardown paths need their own registered disposal/order checks.

The AU commit, Program Change, live sound-edit and native-load-failure success-path tests now observe retired sampler identities weakly instead of prolonging their lifetime across unrelated commits. Their identity, document, MIDI, editor and audio assertions remain; the AU test additionally checks that the original sampler has been released. The dedicated negative test is the intentional retained-owner case.

No patch/library/session schema changes. A failed edit keeps authored and saved setlist bytes, and rollback never resurrects a previously truncated tail. Device route, buffer and installed user data are not modified by the verification tools.

## Acceptance mapping

| #192 criterion | Evidence |
| --- | --- |
| Synthetic detach/eviction ordering | `ExternalGraphTailTests` retains truncation, eviction, rollback and release-before-restart checks. `GraphCompletionFailureTests.unsafeSamplerReleaseRecovery` forces a second sampler owner and verifies forward/rollback/manual-start refusal until release. |
| Rapid live sampler switches beyond the two-tail bound | `VerifySamplerDisposal`: 96 production `Store.choose` switches, 94 verified stopped releases, 15.513645 seconds, maximum two tails / 33 rack-owned nodes, unchanged route at 48 kHz / 512 frames. |
| Local lifecycle evidence | DEBUG support JSON roundtrip retains `retainedPastStop`; the prerequisite records attach/retire/truncate/purge/release facts with channel/generation/engine/attachment state, without sample or plug-in state. |
| Unsafe case stops and preserves the saved patch, with explicit retry | New regression asserts audio-failed/stopped state and failed rollback restart, exact authored/saved bytes, refusal of retry while retained, then finite nonzero playback after release and explicit retry. |
| Original scenario reproduced or explicitly unreproduced | Unreproduced: the original private patch and CoreAudio assertion are unknown. The recorded generated live run follows the same `choose → applyPatch → finishGraphChanges` operation family on Mac16,10 / macOS 27.2. No claim to have reproduced the original trap. |

This acceptance mapping supports closure of the bounded #192 issue after the prerequisite and follow-up are reviewed, required checks pass and the combined changes land on main. It does not close #123, #13, #4 or physical iPad qualification.

## Reproduction and checks

Focused generated tests, all passed (5 passed, 0 skipped, 0 failed):

```
python3 Tests/run-local-library.py . /private/tmp/stagekeys-192-closure-final AudioUnitCommitTests GraphCompletionFailureTests ExternalGraphTailTests SupportDiagnosticsTests NativeGraphRollbackTests
```

CoreAudio access is needed even for these offline tests on this Mac. In the restricted sandbox the unchanged prerequisite aborts while creating Apple's reverb (`comp != nullptr`), before running the regression. With normal CoreAudio access the original tail suite passes; the new retained-owner regression fails on the prerequisite and passes on the follow-up.

The opt-in live probe uses only generated tones in a new `STAGEKEYS_DATA_DIR`, keeps master muted, reads the existing lock-free output meter, and changes no system route/buffer. Compile it against the DEBUG verification core built by the runner (substitute your external build path):

```
xcrun swiftc -DDEBUG -module-cache-path /private/tmp/stagekeys-192-closure-final/modules -import-objc-header Sources/Bridge.h -disable-bridging-pch -parse-as-library -I /private/tmp/stagekeys-192-closure-final -L /private/tmp/stagekeys-192-closure-final -lStageKeysVerificationCore -Xlinker -rpath -Xlinker /private/tmp/stagekeys-192-closure-final -Xlinker -adhoc_codesign Tools/VerifySamplerDisposal.swift -framework CoreMIDI -lz -o /private/tmp/stagekeys-192-closure-final/VerifySamplerDisposal
STAGEKEYS_DATA_DIR=/private/tmp/stagekeys-192-live-NEW /private/tmp/stagekeys-192-closure-final/VerifySamplerDisposal /private/tmp/stagekeys-192-report-NEW.json
```

Committed sanitized run facts and exact relevant input hashes: [Sampler-Disposal-192.json](../Calibrations/Sampler-Disposal-192.json). No audio is captured. 460800 post-protection output frames progressed, with zero invalid output samples. Master mute means this does not prove audible quality or pre-protection sample validity. Counts and the short duration are observations, not memory/CPU limits, latency or soak qualification. The existing default output was used without publishing its potentially identifying UID.

Before the merge-review tail-cap follow-up, unsigned artifact gates passed on the `b282106` production inputs:

```
Tools/verify-release.sh mac /private/tmp/stagekeys-192-mac-final
Tools/verify-release.sh simulator /private/tmp/stagekeys-192-simulator-final
```

Both compile Release code (including the all-build disposal guard), validate the committed project artifacts and enforce sample-free contents/document metadata; the Simulator gate also validates the compiled icon. These are unsigned builds, not installation or physical iPad evidence. Gate inventory, seven runner-regression checks, distribution content validation and diff whitespace checks passed.

Before that follow-up, the default inventory was: **141 programs accounted for, 130 reported passes, 11 explicit private-fixture skips, zero remaining failures** (131 Swift and 10 native C programs).

The initial full run stopped at AU-commit ownership, then resumed after the test/production correction; later success-path tests exposed the remaining test-only strong identity observers described above. Unchanged passing programs retained their results. The final tail ran against this task's byte-identical final verification core. The combined report verifies exact set equality and no duplicates against `Tests/run-local-library.py`'s default plan. It does not erase the failed-attempt logs or count an earlier failing program as passed without a successful rerun. This is complete default coverage across isolated runs, not a claim that one uninterrupted command passed from beginning to end.

Raw local outcomes: `/private/tmp/stagekeys-192-complete-results.json`; final-tail log: `/private/tmp/stagekeys-192-cached-final.log`. The 11 skips require private piano/EXS/MainStage fixtures and are not compatibility evidence. `PianoHeldNoteTests` also reports pass without its optional private fixture: its private-piano case was **not exercised**. No private audio, user sessions or plug-in state is committed. The unchanged separate 23-program reverb sanitizer suite was not rerun locally for this Swift-only ownership change; hosted CI retains that gate. Sandbox compiler-plugin failures and a retry blocked by the initial build's database lock were environment attempts, not passing builds; fresh unrestricted build directories are used for the final gates.


## Merge-review tail-cap follow-up

Review of #197/#206 found one remaining actionable thread: after one batch
retires several active voices, rollback protection can temporarily keep more
than two tails. The next graph transaction previously trimmed overflow only if
it retired another instrument. `enforceRetiredTailCap` now also runs after the
next transaction's silent-tail purge, while stopped. It still never evicts
current rollback voices just to satisfy the target. Documentation now states
this deferred-bound policy rather than claiming an unconditional two-tail cap.

Two isolated generated regressions in `ExternalGraphTailTests` start with three
protected sampler tails, then add a sound to an empty slot (no new retirement).
Both successful and failed/rolled-back edits trim the oldest committed sampler,
preserve every active voice, and prove release before restart using only that
generation's records. The new check fails on `b282106` before the fix.

The five focused disposal/rollback/AU/support programs passed after this final
review change, as did inventory, seven runner regressions, distribution and
whitespace checks. The updated sanitized live record contains the repeated
96-switch run on these exact source hashes. Full hosted Mac/Simulator,
processing/sanitizer and library checks must pass on this follow-up and the
combined parent branch before the authorized merge to main.
