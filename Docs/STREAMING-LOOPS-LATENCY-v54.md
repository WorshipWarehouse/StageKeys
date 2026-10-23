# Streaming, loop and latency regression evidence

Issue: [[P0] Prevent streaming clicks, loop errors and excess MIDI latency](https://github.com/WorshipWarehouse/StageKeys/issues/2).

This change adds regression coverage for the repaired click, streaming, loop and note-lifecycle paths and makes output latency reportable. It does not claim physical MIDI-to-audio parity: the device/buffer matrix below still has to be measured on hardware, and the numbers recorded here are reported values plus offline renders.

## What changed

- `Tests/SamplerBoundaryRegressionTests.swift` builds a synthetic source with a loud 0.1 s attack, a 0.4 s loopable region (160 whole 400 Hz periods) and a quieter post-loop tail, then imports it through the production `AudioController` graph as a managed preset with four representative zones: low (48–59), middle (60–71), high (72–83) and one one-shot tail zone (84–95).
  - Each looped zone is held for six seconds — fifteen loop wraps and far beyond the 0.5 s source region — and checked for note-on block position, per-second held level (a retrigger or truncated decay shows up as a level step), peak (runaway voice), fundamental dominance against the pitches a wrongly selected neighboring zone would produce, and release decay after note-off.
  - Loop-seam continuity compares the rendered maximum sample step across the held region with the source loop's own maximum step, scaled by the measured held gain. The fixture loop is a whole number of periods, so a correct wrap is continuous at unity playback.
  - The one-shot zone must sound its authored 0.1 s and then stop: neither an early truncation nor a loop past the sample end is accepted.
  - Out-of-range region offsets are asserted to throw. `SamplerSplitRegions.assemble` previously validated only the loop range; an edited or corrupt attack offset reached `Data.subdata`, which raises an Objective-C exception and would terminate the app instead of reporting the preset.
- `Tests/SamplerStreamingStressTests.swift` covers the preload and storage conditions:
  - A held note keeps its level while its sample file is moved out of reach, so a loaded instrument has no render-time file dependency in this path.
  - 24 rapid patch changes between two converted instruments, with sustain and overlapping release tails, each still produce audio; the sequence reports no errors and leaves no sounding voice after Panic.
  - A deleted preset and a preset whose samples are offline are both reported through `onError` instead of leaving stale or silent-but-loaded audio. `ExternalInstrumentRack.load` now preflights absolute sample references before attaching the sampler, because AUSampler otherwise accepts an incomplete preset. Only absolute paths and file URLs are checked; other references stay with the sampler's own resolver.
  - Twenty load/reload cycles must stay under a 128 MB resident-growth bound, and the channel must still play afterwards. Original sample bytes and managed preset bytes are compared before and after playback.
- `AudioDeviceController.latency()` (`AudioLatencyChain`) reports the selected device, sample rate, buffer frames and milliseconds, and Core Audio's presentation latency, on both macOS and iOS. `AudioController.latencyChain()` exposes it for diagnostics. These are reported, not measured, values; they exist so the matrix below can record requested versus granted buffering.

## How to run this on a Mac

```sh
Tests/test-library.sh SamplerBoundaryRegressionTests SamplerStreamingStressTests
Tests/test-library.sh          # full offline suite
STAGEKEYS_PIANO_PRESET=/path/to/Steinway.aupreset Tests/test-library.sh RealtimePianoTests
```

`RealtimePianoTests` needs Core Audio output and the private converted Steinway preset. It remains the live-path check for buffer-boundary impulses and resident playback; the new tests are offline and need no output device. `PianoHeldNoteTests` and `PianoFidelityTests` remain the private-fixture long-hold and level checks.

## Device/buffer matrix (to be filled on hardware)

Physical key-to-speaker latency and jitter need a hardware loopback or an external MIDI source with a recorded click track; no VM result is evidence for this table.

| Mac | macOS | Output device | Rate | Requested frames | Granted frames | Reported buffer ms | Presentation ms | Measured onset ms | Jitter (σ) | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| _pending_ | | | 48 kHz | 64 | | | | | | |
| _pending_ | | | 48 kHz | 128 | | | | | | |
| _pending_ | | | 48 kHz | 256 | | | | | | |
| _pending_ | | | 48 kHz | 512 | | | | | | |

Record `AudioController.latencyChain()` for the granted/reported columns, and compare the same instrument and patch against the reference host on the same device and buffer. Any unexplained extra buffering must be written into this document rather than left implicit.

## Limits and remaining work

- The original submission was not compiled or executed: the work was done on a Linux host without Xcode, Core Audio or an output device. Run the commands above and the Xcode build before merging; treat the tests as unverified until then.
- Physical MIDI delivery, device buffer and hardware latency are still unmeasured, and no matrix rows are published yet. `CoreMIDI` events are delivered to the main queue, so the live path's additional scheduling delay is included in that measurement, not in the offline tests.
- The transport is still AUSampler, so "no disk reads on the render thread" is covered by resident playback plus the moved-file test, not by instrumentation of Apple's render callback.
- iOS keeps its existing system loading policy; the moved-file test proves the offline/resident path only and does not establish iPad streaming behaviour.
- Eight-hour soak, memory pressure with a real multi-sample library, and slow external storage are still open; this change bounds reload growth and exercises offline/missing storage with small fixtures.

## Mac verification follow-up — 23 October 2026

Universal macOS Release and iOS Simulator Release builds pass on this Mac (production sources unchanged from the built commit). The sampler boundary and streaming tests now run against Apple frameworks. Fixture corrections neutralize CC1 vibrato for phase-aligned wave checks, compare equal authored root-zone gain rather than assuming an undocumented AUSampler gain, drain eight already-rendered blocks after Panic, and unload a resident voice before checking missing-preset reload failure. These do not remove the loop, pitch, release, missing-content or sample-byte assertions.

All root notes started in render block 0; root held-level spread was below 0.000001 dB and the transposed note below 0.003 dB. The one-shot ended correctly. Resident playback survived moved sample storage; 24 rapid switches and 20 reload cycles passed. Reload resident growth measured 8,339,456 bytes in the accepted run. Original sample/preset bytes stayed unchanged.

The private Steinway realtime regression also passes: upper-note attacks, a second-instrument graph reload and sustain produced maximum step 0.06809379 against offline source reference 0.07149801. This checks the live render path, not physical MIDI-to-speaker latency. The device/buffer matrix, physical iPad policy, slow storage and eight-hour soak remain open, so this PR references issue #2 rather than closing that release gate.
