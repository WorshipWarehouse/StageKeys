# Explicit Program Change mapping

Unconfigured patches no longer respond to Program Change by their position in a setlist. A keyboard's Program Change 0 can therefore not select the first unconfigured patch on startup. Only a patch with `programChangeEnabled == true` and a matching explicit number is eligible. Existing source/channel filtering and Patch Lock still apply.

Patch Settings defaults an absent flag to Off and only displays the number control when enabled. Enabling it assigns one explicit value immediately: the patch's own position when no other enabled patch claims it, otherwise the lowest unclaimed value in 0–127. The value is stored and matched as the raw MIDI byte; the UI labels it 1–128 for hardware that numbers Program Changes that way and names the stored value beside that label. Explicit enabled/disabled mappings retain their existing meaning.

## Display and numbering policy

Program Change recall is documented as a per-patch opt-in with an assigned value in 0–127, and the same documentation warns that some hardware displays 1–128. StageKeys therefore does not pick one numbering silently. `ProgramChangeMapping` in `Sources/Models.swift` is the only conversion point: it decides validity, the 1–128 label, the inverse used by tests and documentation, and the caption text. Patch Settings shows `Program N` and the caption states the raw MIDI value and that only that number selects the patch, so the off-by-one is discoverable where the opt-in is set. Stored setlist data is never rewritten for display, and the persisted value stays validatable as 0–127.

Duplicate numbers are possible only through older data or hand edits. Selection keeps resolving to the earliest enabled patch, as before, and the editor no longer creates a duplicate when it assigns the default number for a newly enabled patch.

Legacy absent flags remain absent on decode/save: no user setlist is silently rewritten, and no schema or source content is changed. Their runtime meaning is now documented as unconfigured/off. Users who relied on implicit positional selection must enable and save the desired patch mappings in Patch Settings. There is no hidden legacy positional mode.

ProgramChangeOptInTests sends real virtual CoreMIDI messages through the production Store. It covers absent flags including patch zero, selection/snapshot/tempo/layer identity, playable notes/pedal after the simulated startup sequence, explicit enable/number, disable, Patch Lock, source channel filtering and JSON persistence. It also covers the display/mapping policy: 0–127 validity, the 1–128 label and its inverse, a caption naming both numbers, and that enabling assigns an unclaimed explicit number, falls back when that number is claimed, and never selects the patch. StoreTests and MIDISetupTests also pass. This reproduces the source-code route with generated messages; it does not record a physical keyboard boot. Issue #88 retains that hardware reproduction and post-fix verification gate.
