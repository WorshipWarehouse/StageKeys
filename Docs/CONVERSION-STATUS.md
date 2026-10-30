# Native sound conversion status — 0.6

## Implemented and verified

Sunday Keys app sampler preset + associated CAF/WAV → managed StageKeys sampler preset: 21 downloaded instruments copied privately and rendered finite nonzero audio at notes 48/60/72. Original Instrument state and sample-zone maps are retained. This validates sampler playback, not the Sunday app's complete per-channel effect/MIDI/patch configuration. No Sunday-owned sounds are bundled in the distributable.

Managed StageKeys sampler preset → exported Apple sampler preset + sample folder: generated-fixture roundtrip passes offline native Apple sampler playback after move/relink. EXS imports use this same managed format. MainStage can host Apple's AUSampler; this is a sampler-preset bridge, not a fabricated MainStage .patch or a full patch roundtrip.

## Still incomplete

All ten Sunday Free MainStage volumes remain original host entries. Complete .patch/.cst conversion requires reproducing the original instruments, effect chains and MIDI behavior, or capturing them. The attempted Auto Sampler run in an isolated scratch concert stalled at Note C1, Velocity 64. No successful capture or converted free-volume instrument is claimed. Scratch edits did not modify the original WorshipKeys concert files.

A sampled synth freezes its timbre/effects and cannot automatically preserve adjustable synth parameters, tempo-synced effects, arbitrary modulation, arpeggiators and chord/sequence logic. These need explicit translation or separate captures and validation. Do not claim lossless bidirectional conversion.

Converted MainStage channels now present their translated source effects for explicit selection. Channel EQ and compression map to the instrument controls; up to three other effects fill the visible slots. Unselected effects, Smart Control assignments and source MIDI transforms remain archived rather than being appended to a rack or claimed as translated. Parallel/send topology and additional EQs/compressors are reported as omissions.

Sunday Sounds explicitly states that existing MainStage/Live patches cannot directly transfer to the Sunday Keys app: https://support.sundaysounds.com/article/3162-can-i-transfer-my-existing-sunday-keys-patches . StageKeys' importer/exporter does not alter Sunday Keys databases or bypass account entitlements. Loading exported instruments back into Sunday's app has not been established.

## Current native library

- SK App Flute Organ Pad v1_1
- SK App Flute Organ Lead v1
- SK App Warm Pad 1 v1_1
- SK App Warm Pad 1 v1
- SK App Tiney Roads v1_1
- SK App Simple Worship Arp v1_1
- SK App Trombone Longs Quartet v1
- SK App Clean Dirt v1_1
- SK App Super String Pad v2_4
- SK App Retro Bell Lead v1
- SK App Felt Piano v1_6
- SK App Wispy Violin Slow Waves v1_1
- SK App Retro Bell Lead v1_1
- SK App Gently Now Lead v1
- SK App Sub Bass v1_1
- SK Una Corda Felt 2_3
- SK App SK Glockenspiel v1
- SK App Thick Staccato Strings v1
- SK App Trance Lead v1_2
- SK Una Corda Felt Spft v1_2
- SK App DX E Piano 1 v1
