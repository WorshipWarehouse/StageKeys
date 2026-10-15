# Library Note Range — v0.24

## Reference observations

The accessible Sunday Keys Mac library exposes All, Full Range, Left Hand, Mid Range and Right Hand. These are overlapping sound tags rather than exclusive numeric keyboard splits. The following memberships were inspected without adding sounds or confirming source-patch changes:

| Filter | Demo results |
|---|---|
| Left Hand | Gently Now / Seq; Sub Bass |
| Mid Range | Flute Organ / Mono Lead; Retro Bell Pad |
| Right Hand | Clean Dirt / Chiff Lead; Flute Organ / Mono Lead; Trance Lead |
| Full Range | DX E Piano 1 / Ballad; Retro Bell Pad; Simple Worship Arp; SK Felt Piano / Room; SK Glockenspiel / Dry; Super String Pad / Velo; Thick Strings / Staccato; Tiney Roads / Warm; Trombone / Quartet Longs; Warm Pad 1; Wispy Violin / Waves |

With Type set to Acoustic Piano, Felt Room remained in the results. All four Note Range choices remained visible even though only that piano matched. This establishes overlapping type membership and fixed Note Range choices in the inspected workflow; it does not establish numeric MIDI boundaries for those tags.

## Implementation

`SoundTags` has optional multi-value `noteRanges` and `types` metadata. The filter matches any assigned range and combines with search and other facets. Fixed choices remain selectable even when they produce no results. Active values in other filter columns also remain visible in an empty result set so they can be cleared. Not Tagged is a StageKeys extension for imported sounds whose source recommendation metadata is unavailable.

Felt Room receives the verified Full Range tag and both Acoustic Piano/Felt Piano type tags. The existing generated library variant receives only missing metadata; its sound, effects, playable range, gain and routing are preserved. An explicit empty tag array survives reopening, so clearing tags does not cause automatic reassignment. The original StageKeys voices are explicitly full-keyboard sounds. Other imports are not assigned guessed source ranges from filenames or key-zone thresholds.

A library row's Note Range context menu toggles multiple tags and can clear all tags. This edits personal library metadata, not the channel's playable-key endpoints. Name-derived tag refreshes retain explicit range/type tags. Converted archive rows share annotations and rating identity with their playable entry, including explicit clears. Archive saves reject duplicate, unknown or oversized range/type metadata.

The context menu and Not Tagged choice are StageKeys extensions; the reference's metadata-editing workflow was not inspected. Complete original-library tagging, Recommended sorting and exact recommendation algorithms remain outstanding. Full 1:1 library or audio parity is not claimed.

## Verification

`Tests/test-library.sh` includes overlapping range/type matching, fixed choices under narrow filters, unknown metadata, multi-select toggles, legacy JSON decoding, missing-metadata migration, explicit clears, inferred-tag refresh, malformed-tag rejection, archive aliases and preservation of the actual sound's key range and other settings.

Universal Apple Silicon/Intel Mac and iPhone/iPad simulator Release builds are checked. Native Mac verification covers choosing Note Range, Full Range/Felt Room results, Acoustic Piano/Felt Piano membership, empty Right Hand results with fixed choices, and Cancel preserving the user's saved patch and library. Physical mobile interaction remains outstanding.
