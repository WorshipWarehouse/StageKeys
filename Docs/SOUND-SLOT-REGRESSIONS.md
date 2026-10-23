# Sound-slot regression coverage

Refs #16. Store mutation methods now refuse stale/out-of-range slot indices, nonfinite/out-of-range faders, invalid key ranges, effect indices and malformed layer settings before touching the session/audio graph. This prevents invalid fader values reaching integer MIDI conversion and prevents a dismissed/stale editor from indexing a nonexistent sound. Existing valid edits retain their behavior.

`AllSoundSlotsTests` plays every slot independently through the actual offline output graph, then checks reordered layer effects/snapshot state and exact session retention after invalid edits. The existing Tonic Pad test covers power/root independence, saved per-patch lock recall, smooth shimmer updates and library-free playback. This is not a complete manual test of every UI action, imported AU, controller, Trash/restore or physical-device transition; those release gates remain open.
