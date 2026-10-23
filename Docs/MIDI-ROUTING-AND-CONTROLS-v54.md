# External MIDI routing and controller setup

Issue: [[P1] Finish external MIDI routing and controller setup](https://github.com/WorshipWarehouse/StageKeys/issues/15).

This increment covers output discovery/reconnect and loop prevention, controller learn conflicts, and persistence for settings that previously reset on launch. Physical-device verification is still outstanding and is listed with the exact checks needed.

## External MIDI outputs

- Destination discovery is cached and invalidated by a Core MIDI client notification block (`.msgSetupChanged`, `.msgObjectAdded`, `.msgObjectRemoved`, `.msgPropertyChanged`). Previously the picker only refreshed when reopened, and `send` re-enumerated every endpoint for every event — a snapshot fade sends CC 7 per layer at 30 Hz.
- A send now resolves the persisted unique ID in the cache, re-enumerates once if it is not found, and throws a clear "disconnected" error instead of dropping the event. Offline endpoints (`kMIDIPropertyOffline`) are never used.
- `ExternalMIDIRouting` orders outputs: the hosted StageKeys port first, then online devices by name, then offline devices, so an unplugged interface stays visible as `Offline` rather than silently vanishing.
- Loop prevention: a destination whose unique ID resolves to StageKeys' own virtual source is never a send target (`ExternalMIDIRouting.isLoop`). `MIDIInput.ignoreSources` additionally excludes the app's own source from the input port by unique ID, so a renamed or loopback-mirrored port cannot feed output back into the input. The old name-only filter is retained as a fallback.
- The Settings MIDI tab lists every output with its status and a **Test** button (middle C, 400 ms) for verifying hardware or a receiving app, plus **Refresh MIDI Outputs**. The Library's External MIDI collection and Settings now read the same published list, so a setup change appears in both.
- Channel mapping is unchanged in behaviour and now asserted: the output channel lives in the status byte the layer already stores, and is not rewritten by the new caching path.
- Persistence stays keyed by `kMIDIPropertyUniqueID` per layer; an output that is missing at launch is reported when the layer sends, and an output that returns is usable after the next notification or refresh.

## Controller setup

- Input acceptance moved into `MIDIControllerRules.accepts`, which encodes the documented meaning of the two slots: `-1` = any source/channel, `-2` = unused. The behaviour is unchanged, but it is now a pure rule with tests instead of an inline closure, so the "None" setting cannot silently start accepting events in a later edit.
- Velocity scaling moved into `MIDIControllerRules.velocity`. It clamps an inverted or out-of-range minimum/maximum instead of producing a reversed or negative response.
- MIDI learn now reports conflicts instead of silently stealing a CC. `MIDIControllerRules.assigning` moves the controller from any previous target, keeps one CC per target, keeps the legacy CC→sound-level map and the named-control map exclusive, and returns the displaced owner so the store can show "CC 20 moved from Master Level to Next Patch". Reserved controllers (CC 1, 64, 120, 123) and invalid targets are rejected.
- **Reset All** in the MIDI Learn sheet clears every learned assignment, keeping the fixed modulation, sustain, panic and program-change routes so the keyboard remains usable.
- Persistence: the metronome preference and the hardware buffer size are now written to `settings.json` and reapplied at launch. The buffer is only restored when the current device reports it as settable and different, and an unsupported size is dropped instead of failing startup. Settings written before these fields existed still decode.
- Device status: the existing source list, offline device list and MIDI monitor are unchanged; the MIDI Learn sheet's Reset All and the output list close the gaps the checklist called out.

## Tests

- `Tests/MIDISetupTests.swift` (new, no hardware): velocity scaling endpoints/midpoint/narrowed/inverted ranges, primary/secondary acceptance including the unused `-2` slot, learn conflict displacement plus per-target exclusivity and reserved/invalid rejection, destination ordering with virtual/online/offline entries, loop and offline resolution, and session-settings round-trip plus legacy decode and out-of-range rejection.
- `Tests/ExternalMIDITests.swift` (requires Core MIDI, no external app): now also asserts the hosted port is listed first and stays virtual across a refresh, that channel 3 is carried in the status byte, that an unknown destination throws instead of dropping, and that the loop predicate rejects the app's own source.
- `Tests/MIDIInputTests.swift` is unchanged and still covers plug-and-play input, two sources/channels, stable refresh, sustain, note-off, unplug and the surviving input.

Run on a Mac:

```sh
Tests/test-library.sh MIDISetupTests
Tests/test-library.sh ExternalMIDITests MIDIInputTests
```

## Verification status

Not built or executed: this change was prepared on Linux without Xcode or Core MIDI. The touched sources and tests parse under a Swift 6.0.3 toolchain but have not been type-checked against Apple's frameworks, and no external app or device was exercised.

Pending manual checks:

- Create an IAC bus in Audio MIDI Setup, send from a StageKeys MIDI layer to it, and confirm note/CC delivery, offline/reconnect behaviour (toggle the bus off and on), and that the Test button reaches a monitor in another app.
- Verify the hosted "StageKeys to External App" port still appears in a receiving app after a sleep/wake cycle and after unplugging an unrelated interface.
- Plug/unplug a USB keyboard: confirm the input list, primary/secondary "Not Connected" annotation and automatic reconnection, and that a loopback-mirrored port is not opened as an input.
- Learn the same CC onto two targets and confirm the conflict message, per-target exclusivity, Reset All, and that reserved CCs cannot be learned.
- Set a velocity range, metronome and hardware buffer, relaunch, and confirm all three are restored; then select a device that rejects the saved buffer and confirm startup still succeeds.
- iPad/iPhone Core MIDI routing and Bluetooth/network MIDI sessions are untested; the checklist's "test with real external apps/devices" criterion stays open until these are recorded.

## Remaining gaps

- There is no per-destination channel remap or output-latency compensation; each layer stores one output and one channel.
- Pitch bend, aftertouch, program change and SysEx are not forwarded to MIDI layers, and incoming MIDI is only forwarded as note on/off plus pedal/level CCs.
- The MIDI monitor is a flat 15-line log without filtering by device or message type.
- MIDI learn addresses host controls only, not Audio Unit parameters (issue #12's generic editor writes parameters directly).

## Mac verification follow-up — 23 October 2026

Universal Mac and iOS Simulator Release builds pass with the inherited AU fixes. Manual MIDI refresh now calls the output enumerator rather than reading the existing cache. A production-store regression creates a real CoreMIDI destination without yielding to queued setup notifications and proves explicit refresh adds/removes it.

MIDISetupTests, ManualMIDIDestinationRefreshTests, ExternalMIDITests and MIDIInputTests pass. CoreMIDI is allowed to coalesce messages, so the output test traverses every packet and checks decoded three-byte messages rather than assuming one message per packet. The test waits for all three output messages. Input coverage includes post-launch attachment, two source/channel identities, stable refresh, sustain/note-off, unplug and surviving input. The real Alesis was left idle; these synthetic endpoints do not constitute USB power-cycle or external IAC/hardware receiver certification. Broader physical-device acceptance remains open under issue #15.
