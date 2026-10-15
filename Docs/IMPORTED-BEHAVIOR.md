# Imported rack behavior — version 0.15

All 213 previously installed free-library conversions now have retained rack metadata. 212 contain translated processing, with 430 effect instances and 212 mapped effect macros in total. Original sample bytes and references are unchanged. User setlist and session settings files were byte-identical before and after the library metadata upgrade.

## Supported in this release

- Single outer serial chains: EQ3 → StageKeys Equalizer (shelf/mid-band approximation), Compressor2 → StageKeys Compressor (saved threshold, attack, release, ratio, dry/wet and output), Reverb → PrimaVerb approximation (saved size, predelay, tone, modulation and dry/wet). Device bypass and serial order are preserved among translated effects.
- Imported processing has its own chain before the three performance FX slots. Up to twelve effects are supported, without requiring external plugins.
- Root-rack effect macro mappings retain names, values and ranges. One macro can affect multiple parameters, including complementary dry/wet controls. Saved effect values remain authoritative until a macro is moved. Frequency ranges interpolate logarithmically; other destination values interpolate linearly. Source mapping curves may differ.
- Sound Settings → Settings → Imported Sound Controls exposes macros, effect bypass and detailed parameters. Confirm/Discard uses the existing audition lifecycle. Imported rack state persists with sounds, patches and snapshots, and interpolates during snapshot transitions.
- Serial Pitch and Chord MIDI chains translate to explicit note mappings when no other active MIDI processors or scaled chord velocities are present. Note-off releases all generated notes. This was verified with synthetic fixtures. None of the 213 real archive conversions met these narrow MIDI-chain conditions; their MIDI processing remains flagged.
- Existing imported channels acquire the matching library rack metadata on patch activation while preserving user channel settings, levels and performance FX.

## Remaining differences

Nested/parallel branch effects need independent processing voices. Saturator, asymmetric/ping-pong delays, arpeggiators (including rate enums, groove, hold, retrigger and velocity decay), sampler-target macros, nested-rack macros, source envelope curves, filter/LFO modulation and advanced sampler behavior are not yet translated. Import Notes identify omissions. Reverb, EQ3 and compressor detector behavior are approximations, not sonic equivalents. Unsupported effects between translated effects can change the chain's sound substantially.

Ableton's public MIDI effect reference explains Pitch, Chord and Arpeggiator behavior but does not establish the archive's numeric rate/style enum mapping: https://www.ableton.com/en/live-manual/11/live-midi-effect-reference/

## Library UI

Compared again with the installed Sunday Keys demo library: revised facet/results proportions, wider search and collection controls, solid selection highlighting, no added radio circles on sound rows, a direction-based sort icon, and direct selection of individual imported volume collections. Individual volume views show playable sounds; original host-only entries remain in MainStage Archive. Selecting a result still requires Add Sound to commit. Facet changes swap columns instead of creating duplicates. Complexity dots are not fabricated for imports with no source metadata.

## Verification

Synthetic source tests cover saved parameter values, bypass/order, a macro mapped to both dry and wet, full-range macro snapshot transitions, serial Pitch/Chord output and note-off, out-of-range notes, persistence and parallel-rack safeguards. Offline production-graph rendering exercises a sound from every volume, plus a multi-bank imported chain. Existing library, performance and plug-and-play MIDI regressions pass. Live GUI verification confirmed the imported Reverb macro changed dry/wet together (64/127 → 49.61% dry, 50.39% wet), and verified Volume 1 contains 87 playable entries without host-only duplicates. Mac and iOS builds are checked separately; no physical iOS playback test is claimed.
