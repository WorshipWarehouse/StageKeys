# Audio device failure state and diagnostics

Implementation follow-up, 3 November 2026, for #123. It covers explicit output-route and buffer changes made from Audio Settings. The separate engine-configuration path used for unplug/replug and sleep/wake is being changed independently in #130 and is not modified here. This does not reproduce the reported intermittent AVFAudio `-1` and does not close #123 or #110.

## Source defect

Source inspection identified the behavior below; the generated test additions were not executed here (see verification status).

`PerformanceStore.selectAudioOutput` and `setAudioBuffer` called the generic Store `panic()` before changing the device. That method deliberately clears the Tonic Pad selection (`tonic = nil`) and disables the metronome (`metronome = false`), so a successful or rejected output/buffer change silently switched off both performance choices. The pad and click were not restored by the subsequent automatic or explicit start unless the patch had a locked Tonic state.

`AudioDeviceController.transaction` also wrapped a failed resume as `AudioDeviceError.restartFailed(error.localizedDescription)`, and the Store displayed that string directly. That is the path that can show `The operation couldn’t be completed. (com.apple.coreaudio.avfaudio error -1.)`; it did not record an operation-scoped diagnostic.

## Implemented behavior

- Explicit device-setting operations suspend performance note ownership while preserving the pad selection and click choice. The pad note is retriggered only when audio is running again; if the engine is still stopped, the existing resume-after-start ownership replays it on the next successful start. If a required device restart fails terminally, the failed state stays visible and sounding notes are cleared, while pad/click intent is retained for a successful retry. Unexpected engine configuration changes now use the same intent-preserving recovery cleanup; manual Stop revokes resumption. See [pad recovery intent](PAD-RECOVERY-INTENT.md).
- A rejected transaction now records `AudioChangeDiagnostic.Phase.audioDevice` with the underlying numeric cause, current sample rate, current buffer frames when the device can still be queried (`nil` when unmeasured), engine state and graph generation. The diagnostic deliberately does not attach a prior rack graph failure or enter graph-recovery ownership.
- Device failures no longer display or serialize the raw AVFAudio/Core Audio description. Messages state whether the previous output is still active or audio is stopped, and direct the performer to Audio Settings and Start Audio. Support Diagnostics reports the numeric code and allowlisted domain.
- `AudioDeviceError.resumeFailed` exposes only the underlying numeric code; known device errors now include a recovery action. The underlying error object is used only to record the allowlisted support domain and code.

The pad is retriggered, not phase-continuous. The click clock is reset by the existing panic path. Neither is claimed as seamless audio.

## Regression coverage

`SupportDiagnosticsTests` covers a `com.apple.coreaudio.avfaudio -1` device cause: the message is numeric and actionable, contains no raw description or generated private text, differs between running/stopped states, and round-trips through the support report.

`GraphCompletionFailureTests` now also asserts a failed rollback is recorded separately (`rollbackSucceeded == false`, `rollback` code present, stopped UI), and a rejected device/buffer transaction in manual rendering preserves the selected pad and click, retriggers the pad, records the `audioDevice` phase, and does not expose raw error text.

Expected baseline failures for the device assertions: the previous source clears `tonic` and `metronome` and does not set `lastChangeFailure` for a device rejection. Rollback assertions document existing behavior.

## Verification status

This change was prepared on a Linux Freebuff host without Xcode, macOS AVFAudio or an output device. Nothing here was compiled, executed, or measured in this session. Run the focused programs on a Mac, with the build directory outside the checkout:

```
python3 Tests/run-local-library.py . /private/tmp/stagekeys-device-failure SupportDiagnosticsTests GraphCompletionFailureTests
```

`AudioDeviceTests` remains on demand because it needs a live output device. Real route changes with the AudioBox, competing applications, unplug/replug, sleep/wake and the actual intermittent `-1` reproduction remain unverified. Unplug/replug and sleep/wake runtime behavior are covered by #130, not this change. No GitHub issue was edited or closed and no distribution action was performed.

## Reproducible macOS procedure

Record macOS version, StageKeys build, output route, sample rate, buffer, active sound kind (native sampler or named Audio Unit), patch and foreground competing audio apps. Do not record private paths, plug-in state or user content.

1. Start audio on the target route and play a held note with sustain. Repeat each edit below at least 20 times while sampling: a native sound replacement, an effect insertion and removal, a patch-setting change (tempo, transpose, EQ, compressor, volume), and an output-route or buffer change.
2. Between runs, keep the Tonic Pad enabled on a known root and the metronome enabled. Confirm both remain enabled, the pad remains audible after a route/buffer change, and no stuck key or pedal remains.
3. Repeat with a hosted Audio Unit, including its editor open/close and repeated same-instrument state edits. Watch for silence, clicks, duplicated notes and graph/resource growth (Activity Monitor memory and CPU, plus Debug-owned node/tail counts where available).
4. On any failure, run **Help → Copy Support Diagnostics** before dismissing the banner. Record the `phase`, slot, graph generation, engine-running state, sample rate, buffer frames, numeric code/domain and whether the previous sound/output stayed active. Distinguish a failed device change from a failed sound/graph edit by the reported phase.
5. To exercise the deterministic regressions, run the focused commands above on the Mac. They inject failures at preparation, candidate attachment, graph connection, state restoration, sampler restoration, engine restart and rollback boundaries. Label this fault-injection evidence, not a real `-1` reproduction.
6. For a real `-1` attempt, use the AudioBox with a competing audio application, then change the output route, buffer, sound or effect until the alert appears. Capture the support report and note the triggering control, route, rate and buffer. If it does not occur, report no reproduction rather than substituting the injected failure.
7. Finish with the unsigned universal Mac artifact/content gate (`Tools/verify-release.sh mac <build-dir>`, build directory outside the checkout). Simulator/artifact compilation is not device qualification.

## Audit correction

The click model is now restored before an accepted device transaction saves settings, while the rendered click stays suspended until resumption. The initial defer-only code saved `metronomeEnabled: false` on success. Generated accepted-device/buffer hooks now exercise actual Store save paths and assert the saved click remains enabled. This complements rejected-operation tests; it is not a physical device success test. Startup recovery from #130 is integrated and tested with this change.
