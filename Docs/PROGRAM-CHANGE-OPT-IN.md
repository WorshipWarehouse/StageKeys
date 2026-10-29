# Explicit Program Change mapping

Unconfigured patches no longer respond to Program Change by their position in a setlist. A keyboard's Program Change 0 can therefore not select the first unconfigured patch on startup. Only a patch with `programChangeEnabled == true` and a matching explicit number is eligible. Existing source/channel filtering and Patch Lock still apply.

Patch Settings defaults an absent flag to Off and only displays the number control when enabled. Enabling it explicitly assigns the current position if no number was previously stored; the UI displays MIDI numbers 1–128 while storing 0–127. Explicit enabled/disabled mappings retain their existing meaning.

Legacy absent flags remain absent on decode/save: no user setlist is silently rewritten, and no schema or source content is changed. Their runtime meaning is now documented as unconfigured/off. Users who relied on implicit positional selection must enable and save the desired patch mappings in Patch Settings. There is no hidden legacy positional mode.

ProgramChangeOptInTests sends real virtual CoreMIDI messages through the production Store. It covers absent flags including patch zero, selection/snapshot/tempo/layer identity, playable notes/pedal after the simulated startup sequence, explicit enable/number, disable, Patch Lock, source channel filtering and JSON persistence. StoreTests and MIDISetupTests also pass. This reproduces the source-code route with generated messages; it does not record a physical keyboard boot. Issue #88 retains that hardware reproduction and post-fix verification gate.
