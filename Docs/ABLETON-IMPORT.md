# Direct Ableton free-library conversion — StageKeys 0.13

All ten free Ableton archive volumes were downloaded from the links on Sunday Sounds' free archive page. The native importer processed 216 presets; 213 sample-map conversions passed and are installed in the local StageKeys library. This Ableton catalogue differs from the 358-bundle MainStage catalogue; these counts do not establish conversion of every MainStage variant.

Original audio is copied byte-for-byte, including the packs' FLAC files. No host playback capture, sample-rate conversion or resampling is used. The installed native format is Apple AUSampler AUPRESET with managed original audio references. Playback requires neither Ableton nor MainStage.

| Volume | Presets | Imported | Excluded |
|---|---:|---:|---:|
| 1 | 88 | 87 | 1 |
| 2 | 24 | 22 | 2 |
| 3 | 13 | 13 | 0 |
| 4 | 13 | 13 | 0 |
| 5 | 13 | 13 | 0 |
| 6 | 13 | 13 | 0 |
| 7 | 13 | 13 | 0 |
| 8 | 13 | 13 | 0 |
| 9 | 13 | 13 | 0 |
| 10 | 13 | 13 | 0 |

## Exclusions

- Volume 1, Deep Inhale – Layered Patch: missing GrandPiano-A#-1-ff.aif, a sample not included in the pack.
- Volume 2, Chord Trigger Preset: MIDI processing only; contains no sampler instrument to import as a sound.
- Volume 2, Wow Synth: saved rack selector is 79, while its sample branches occupy 80–108. No samples are active at that saved setting. The importer does not silently choose a different rack state.

## Fidelity and verification

2,157 mapped-root playback checks passed with each layer isolated. Copied sample-reference hashes were checked 2,170 times during local installation. Generated fixtures verify multiple layers, key/velocity gates, loop metadata, unchanged audio and rejection of malformed XML, entities, unsafe paths and invalid archive bounds. Production Store/channel/effect-graph playback passed for a sound from every volume. Store, library and CoreMIDI regressions passed. Mac and iOS builds passed; physical mobile playback remains unverified.

Converted maps preserve supported zones, roots, sample endpoints, loop positions, active saved layers and basic amplitude envelopes. Native sampler connection IDs are rebased per layer, and repeated references share waveform IDs. The app accepts ALP packs directly, or ADG/ADV presets with an explicitly selected sample folder. Native UI testing confirmed duplicate pack import skips existing entries (Volume 3: 0 new, 13 existing, 0 failures), and library Import Notes are visible. Existing local sounds and setlists were retained. No sound assets are bundled in the distributable app/source archives.

These are sample-map conversions, not complete Live rack emulations. Live effects, MIDI chains, macro assignments, filter/LFO modulation, velocity response, envelope curves, zone crossfades and some loop behavior still require translation or differ. A musical arp preset's underlying tone can play, but its Live-generated rhythm is not recreated automatically. Import Notes make those limits explicit for each sound. Whole-patch 1:1 equivalence is not claimed.
