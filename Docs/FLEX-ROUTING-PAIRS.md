# Detected stereo output pairs — #107 stage 1

Stage 1 of [#107](https://github.com/WorshipWarehouse/StageKeys/issues/107).
Software increment only: no audio-graph routing change, no per-sound destination,
and no hardware qualification. The issue stays open.

## Problem

StageKeys Settings → Flex Routing previously stated only that multiple hardware
outputs and category routing were not implemented. The app already enumerated an
output device's real channel count for the device picker, but nothing derived or
reported which stereo pairs that device can actually carry. Without that,
per-device routing work cannot distinguish "no such output" from "not
implemented", and a future saved destination could be silently substituted.

## Implemented scope

- `FlexRouting` derives stereo pairs from a device's reported output channel
  count. Pair 0 is Output 1–2; a device reporting one channel has no pair, and an
  odd trailing channel is reported as unpaired rather than paired with a channel
  that does not exist. Derivation is bounded to `FlexOutputPair.maximumPairs`
  (16), so a malformed driver cannot grow the UI or the diagnostics report.
- `FlexRouteState` resolves a requested pair index against the selected device:
  available, mono device, no reported outputs, stale pair, or device capability
  unknown. A stale index is named, never replaced by another pair.
- `AudioDeviceController.outputChannelCount()` reads the selected device's
  reported output channels without starting audio, changing the route or
  enumerating names. Offline rendering reports `offline`, as the rest of the
  device controls do.
- Settings → Flex Routing lists the selected output, its reported channel count
  and the detected pairs, marks pair 0 as the only active one, and states plainly
  that nothing is routed to a pair it only reports.
- Local support diagnostics gain an optional `usableOutputPairs` count. It is a
  bounded number, contains no device identifier or route name, and older reports
  still decode without it.

## Deliberately not implemented

Category defaults, per-sound overrides, per-device persisted routing, routing the
Tonic Pad or click separately, actual mixing to a second pair, unavailable/stale
*saved* destinations (there is nothing saved yet), and every physical
multi-output, sample-rate, unplug/reconnect and session-migration check listed in
#107 remain outstanding. Because no destination is stored and no audio is moved,
this change cannot silently route a sound to a different output.

## Verification

`Tests/AudioDeviceInventoryTests.swift` (default library gate) now covers pair
derivation for 0/1/2/4/7/4096-channel and maximum-count devices, pair titles,
odd-channel reporting, the pair bound, and every resolution state including a
negative index, `nil` capability and a stale index that must be named rather than
substituted. `Tests/SupportDiagnosticsTests.swift` covers the bounded, optional
pair count and legacy decoding.

These are deterministic value-model checks. They were not executed in the Linux
cloud workspace, which has no Swift compiler or Apple SDK; the macOS
`library`/`builds` jobs on the pull request are the execution evidence. No audio
device, multi-output interface, physical iPad or latency measurement was used, so
nothing here qualifies hardware routing, audible output or #107's remaining
acceptance criteria.
