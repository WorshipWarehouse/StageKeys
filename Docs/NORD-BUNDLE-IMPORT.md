# Nord Stage 4 bundle admission and standalone pianos

Refs #245; sample instruments and full artist programs remain #246 and #247.

A user-selected `.ns4pbundle` is read without extracting archive paths. The
preview lists manifest program dependencies and distinguishes untranslated
programs from the pianos that can be explicitly inspected and imported. Bundle
inspection installs nothing. Each selected piano uses the existing transactional,
source-identified experimental attack-only Nord conversion. Importing a piano
never means its artist program was recreated.

The independent reader admits bounded single-disk ZIP containers with stored or
raw-deflate entries, validates local/central headers and program checksums,
rejects path collisions, traversal, symlinks, encryption, overlapping spans,
missing dependencies, malformed manifests and oversized allocations. Selection
rechecks the directory/manifest fingerprint and validates the selected payload's
ZIP checksum; piano conversion binds its own SHA256 identity. The bundle
fingerprint is not a whole-source cryptographic digest. Cancellation and Discard
clear uncommitted previews. No vendor asset is bundled with StageKeys.

## Evidence, 18 November 2026

Generated tests exercise stored/deflate payloads, unchanged sources, stale
previews, manifest dependencies, unsafe paths, encrypted/oversized inputs,
corrupt programs/pianos, truncation, explicit confirmation, cancellation,
Discard, native conversion and restart. The focused bundle/import/rollback suite
passed 3 tests, with no skips or failures. Distribution tests also passed and
reject `.ns4p`/`.ns4pbundle` vendor content from app artifacts.

The user-selected Danny Lopez bundle contains 32 programs, nine pianos and three
sample instruments. Private production-reader inspection validated the manifest
and all 32 program containers and all nine piano mappings. A separate private
qualification helper explicitly selected, decoded and installed each piano,
then rendered keys 36, 60 and 84 at velocities 20, 57, 58, 100 and 127 through
the native offline audio graph. All nine produced finite, nonzero output in all
135 sampled cases. A fresh Store retained all nine catalog entries. The source
SHA256 remained
`6203b01e965d4ad986cfb130112eed286ddf5eadffd731af2977055c436ff624`.
Private reports, source bytes, decoded audio and installed assets remain outside
the repository. The helper used the optimized test core with the same bundle
parser and conversion code; it does not qualify subsequent UI-only changes.

These are bounded conversion/playback checks on an M4 Mac with macOS 27.2.
They do not establish Nord hardware sound equivalence, a listening comparison,
release/resonance/pedal equivalence, all-key coverage, hardware latency, memory
headroom, an eight-hour soak, visible UI qualification, or other Mac models.
The three NSMP4 instruments and the synth/organ/effects/layering/program behavior
are untranslated. Full artist-bank playback remains unavailable.
