# EXS logical loop positions and physical tail storage

## Corrected in 0.36 / conversion version 5

The user's live capture disproved the v4 repair described below. V4 copied logical loop positions directly from the consolidated CAF; those positions can point into a different note. The recorded D5 decay acquired a component near 830 Hz a few seconds after its ~588 Hz attack. Checking only for a new attack after ten seconds missed the defect.

These factory EXS zones have separate physical tail start/end fields at zone-body offsets 116/120. The logical tail begins at the attack endpoint. Its length equals physicalTailEnd − physicalTailStart, and logicalLoopEnd − attackEnd. Playback now copies the entire physical tail after the attack, and maps the loop relative to that tail: nativeLoopStart = attackLength + logicalLoopStart − attackEnd. The physical tail can precede the attack in the CAF. All 275 affected modern Steinway zones and 220 legacy zones satisfy the length identity. Missing or inconsistent tail storage is rejected instead of inventing a region.

No original audio bytes are changed or resampled. Existing v3/v4 generated presets receive backed-up tail metadata updates; filters, gain, tuning, effects and user settings remain intact. V5 also restores logical endpoints previously bounded against the physical file length; physical tail bounds are checked independently. The private D5 regression now measures the intended pitch against the foreign pitch during the 2.8–3.3 second tail, rather than relying only on late silence.

## Historical v4 implementation and verification (superseded)


Version 0.35 (native conversion version 4) repairs a consolidated-sample mapping defect. An EXS zone may have an attack endpoint before its loop start. The original converter extended the sample end to the loop end and played the intervening frames. In the factory Steinway Piano 2 consolidated CAF, those frames can contain neighboring notes. This can produce an unintended quiet attack during a held note.

New conversion retains the original attack endpoint as zone metadata. Existing generated instruments can be upgraded through Import Sounds → Update Converted Sampler Playback. The upgrade verifies the retained EXS digest and matching generated zone boundaries, backs up the preset, and leaves synthesis controls, rack effects and user settings intact. Edited or ambiguous zone maps are rejected rather than guessed.

At playback, supported interleaved, uncompressed PCM CAF regions are assembled into a temporary CAF containing the original attack frames followed immediately by the original loop frames. PCM bytes, channel count, sample rate and sample format are copied unchanged. This is lossless frame assembly, not resampling or a recording. Original CAF files and saved file references remain untouched. Both the main sampler and controller-bank branches use the prepared map. Temporary data is cached within the app process; switching sounds does not rebuild the same regions repeatedly.

Compressed and unsupported split-region encodings are rejected explicitly. Loop transition interpolation, EXS envelope shapes, and the exact MainStage Lush filter circuit are still not proven identical. This change fixes an identified mapping defect; it does not establish complete sound parity with MainStage or Sunday Keys.

Validation: EXSSplitRegionTests checks stored PCM sample equality, original-file preservation, bounds rejection and actual held-note audio excluding a deliberately loud gap. EXSVoiceUpgradeTests checks a source-backed Steinway upgrade, assembly of its real split regions, and preservation of synthesis controls and original audio hashes.

Release verification on the private factory Steinway Piano 2 fixture: 275 split zones migrated, with existing synthesized controls and complete source CAF hashes preserved. Synthetic held-note peak dropped from 0.032664 in the attack to the intended 0.016332 loop tail. Realtime upper-note step was 0.034968 versus offline reference 0.034964; the streaming click regression passed. Universal Mac (Intel/Apple Silicon) and iOS Simulator release builds passed. The app source/bundle separation check found no sampled library content.

## D5 follow-up

The reported symptom was a quiet minor third above D5 after roughly ten seconds. A dedicated 15-second native-engine render of MIDI 74 and 86 (both common octave-label conventions) with the repaired modern Steinway at velocity 83 contained no late attack: both were silent from second 9 onward under the currently translated zero-sustain envelope. This validates that fixture and engine path, not every patch or the user's live observation. PianoHeldNoteTests retains this private-fixture regression.

Inspection of the open MainStage Grand Piano channel showed active Channel EQ: +0.5 dB at 1860 Hz and +3.5 dB at 2960 Hz, both Q 0.71; other bell/shelf gains were zero. Tape Delay was tempo-synced to a quarter note, 51% feedback, 170–1900 Hz filtering, 100% dry and **0% wet**. The comparison patch now uses StageKeys' existing Equalizer for the audible EQ boosts. No arbitrary output-gain compensation was applied: matched MIDI/velocity and channel-level measurements are still needed to resolve loudness and velocity-curve differences. The MainStage controls were restored after read-only inspection.

Version 0.35.1 also repairs EQ numeric entry: partial typed values are retained while editing, instead of being clamped/reformatted after each keystroke. Valid values update the sound; invalid or out-of-range input is resolved on commit.
