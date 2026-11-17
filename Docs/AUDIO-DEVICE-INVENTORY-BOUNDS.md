# Bounded audio-device inventory

3 November 2026. Related to issues #3 and #107; this is an independent StageKeys safety fix, not completed multi-output routing or physical reconnect qualification.

## Investigation and implementation plan

At baseline `c4c8da2`, macOS output-channel enumeration queried a variable-sized property, then iterated `UnsafeMutableAudioBufferListPointer` using its embedded count without checking that all entries fit the returned byte count. Channel addition could also overflow UInt32. Device-ID enumeration rounded the queried byte count down to array elements and iterated the original array even if the successful read returned fewer bytes.

The bounded change is confined to `AudioDevices.swift`, its new regression, existing test inventory and this evidence. Keep hardware selection, settings formats, MIDI ownership, render code and current audio state unchanged. Read only on the control thread, retain explicit alignment/lifetime ownership, and refuse malformed inventory before traversal. Failed endpoint queries continue to omit that endpoint; a failed device-list query reports a refresh action through the existing error path.

Property reads now allocate an explicitly aligned buffer with a one-MiB ceiling, preserve the allocation capacity separately from Core Audio's returned size, and copy only returned bytes after checking that size. The ceiling is a safety budget for inventory properties, not a hardware channel limit. Parsing uses unaligned scalar loads from the owned copy; it never follows AudioBuffer mData pointers. Buffer count must fit complete entries, channel summation must fit UInt32, and device IDs require complete words, omit the invalid zero ID, and preserve first occurrence while removing duplicates.

## Reproduction and verification scope

A standalone generated probe of the former unchecked traversal, with a one-entry allocation claiming UInt32.max entries, exited 134 with an AddressSanitizer BUS report in the buffer-list collection traversal. This reproduces the unchecked algorithm's failure on inconsistent property bytes. It does **not** establish that a real device has returned those bytes or caused a reported stage crash.

`AudioDeviceInventoryTests` exercises the production decoder: zero/mono/stereo/multi-stream output, every truncation boundary of a multi-stream list, oversized counts and payloads, overflowing channel totals, deliberately invalid mData bytes that must not be dereferenced, incomplete device IDs and duplicate/zero IDs. It runs in the existing library gate. Exact decoder tests pass with AddressSanitizer on native arm64 and explicitly compiled x86_64 under Rosetta; translated execution is not physical Intel hardware qualification.

No sample/vendor content is used. Multi-output destination selection, category/per-sound routes, per-device routing restoration, actual hotplug/sleep/sample-rate tests and prolonged performance remain outstanding under #107 and the live-recovery issues. Per-sound metering remains separate work under #109; this fix introduces no render callback or meter.

Final local verification: 109 reported passes, 11 explicit skips, zero failures. The known optional private-piano case is unexercised despite reporting pass. Final universal Mac and generic Simulator artifact gates passed, as did both decoder sanitizer targets and the read-only AudioBox inventory/status sanitizer probe (48 kHz / 512 frames). All 219 frozen source/test/project/workflow inputs matched after validation. Exact commands, generated baseline-probe source, limitations and hashes are in [verification](Completion/audio-device-inventory-verification.json).
