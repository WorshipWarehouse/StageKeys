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
- Patch recall is Program Change opt-in only; see [PROGRAM-CHANGE-OPT-IN.md](PROGRAM-CHANGE-OPT-IN.md). An unconfigured patch ignores Program Change, including a keyboard's power-on PC 0, and Patch Settings shows the raw MIDI value (0–127) beside the 1–128 label some hardware uses.
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

## Primary-only notes and the Secondary control surface — 8 November 2026

Issue #15's controller contract says only the selected Primary controller generates patch notes, while the Primary and Secondary controllers may both drive learned UI controls. Before this change both slots fed one acceptance guard in `PerformanceStore.handleMIDI`, so a keyboard configured as the Secondary controller played the patch as well and could hold notes the Primary never started.

- `MIDIControllerSlots` (`Sources/MIDIControlTarget.swift`) encodes the split as a pure value type. `acceptsNotes` consults the Primary slot only; `acceptsControls` accepts either slot and reuses the existing `accepts` predicate, including `-1` = any source/channel and `-2` = unused.
- `handleMIDI` classifies status `0x80`/`0x90` as notes and every other message (CC, Program Change, pitch bend, aftertouch) as a control. The MIDI monitor line is still written before acceptance, so a filtered Secondary device stays diagnosable.
- A source matching both slots is treated as the Primary, so selecting the same device for both slots does not silence it. A Secondary-only setup remains a control surface and the patch has no note source.
- Pedals (CC64), the modulation wheel (CC1), panic (CC120/123), learned CC assignments and Program Change keep working from either controller. Only note ownership moved.
- Slot changes already call `panic()`, which clears every `hardwareNotes` key, so demoting a controller cannot strand a held note.
- Shipped defaults are unchanged: `primarySourceID = -1` (any) and `secondarySourceID = -2` (unused), so a single controller still plays notes and existing settings keep their behavior.

### Tests

- `Tests/MIDIControllerSlotsTests.swift` (new, `Foundation` only, default gate): primary-only note acceptance with per-slot channel filters, Secondary control acceptance, unused (`-2`) and wildcard (`-1`) slots, duplicate slot selection, a Secondary-only setup and a wildcard primary with a channel-filtered secondary.
- `Tests/MIDISetupTests.swift`, `Tests/MIDIInputTests.swift`, `Tests/ProgramChangeOptInTests.swift` and `Tests/KeyboardPerformanceSettingsTests.swift` are adjacent checks and were not modified.

Run on a Mac:

```sh
Tests/test-library.sh MIDIControllerSlotsTests
Tests/test-library.sh MIDISetupTests MIDIInputTests ProgramChangeOptInTests
```

### Verification status

Executed on Linux with the Swift 6.0.3 toolchain: `swiftc -O Sources/MIDIControlTarget.swift Tests/MIDIControllerSlotsTests.swift` builds and the program prints its `PASS` line; `swiftc -frontend -parse` accepts the changed `Store.swift`, rules and test. The repository's Linux gates (`git diff --check` and the `Tests/test-*.py` distribution, catalog, accessibility, preset, pack and library-gate checks plus `.agents/validate-skills.py`) pass.

Not built or executed here: no Apple SDK is available, so `StageKeysMac`/`StageKeysMobile`, the Core MIDI suite and the app-level `handleMIDI` path are unverified in this environment. Still pending for #15:

- Two real controllers (for example a keyboard on Primary and a pad/controller on Secondary): confirm only the Primary plays notes, that learned CCs, sustain and Program Change still work from the Secondary, and that the surviving controller still works after an unplug/reconnect.
- Confirm the MIDI monitor still shows Secondary messages and that a Secondary-only configuration cannot start notes by any route (screen keyboard is unaffected).
