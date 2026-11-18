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

Private user-selected content was also exercised locally. Source identities,
asset inventories, detailed conversion results and reports are deliberately
omitted from this public record. No private source or decoded asset is committed.

These are bounded conversion/playback checks on a development Mac. They do not
establish Nord hardware sound equivalence, a listening comparison,
release/resonance/pedal equivalence, all-key coverage, hardware latency, memory
headroom, an eight-hour soak, visible UI qualification, or other Mac models.
NSMP4 instruments and synth/organ/effects/layering/program behavior are
untranslated. Full artist-bank playback remains unavailable.
