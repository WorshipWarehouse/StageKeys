# Bulk sound import

`Import Sounds → Instrument File` accepts several audio files in one selection.
The batch is one catalog transaction: each file is prepared first, and the
library document is written once, only after every accepted file is ready.

## Scope

- Self-contained sources are imported together: WAV, AIFF/AIF, CAF, SF2 and DLS.
- EXS and AUPRESET instruments still need the folder that holds their samples,
  so they keep the one-at-a-time flow (`Instrument File`, single selection) or
  the folder scanner (`Sampler Folder`). A mixed selection that contains one of
  those files is refused with that explanation instead of guessing a sample
  root.
- MainStage patches, `.stagekeyspack` archives and Nord `.npno` files keep their
  own single-source flows.

## Behavior

- Selection order does not matter: sources are prepared in a deterministic path
  order, and a file selected twice is prepared once.
- An already-installed sound is skipped when the SHA-256 of the selected file
  matches either the entry's managed-file digest or its retained original
  instrument digest. Name-only matches never suppress an import.
- A file that fails to prepare is reported by file name with a bounded reason
  (200 characters) and does not block the rest of the batch.
- Nothing is committed when the batch is cancelled before commit, when no file
  was accepted, or when the compare-and-swap in `SoundLibrary.commitImport`
  detects a concurrent library edit. In those cases the existing
  `sound-library.json` bytes are unchanged, and the import view reports
  `Import not committed: …`.
- The final message counts what happened: added sounds, skipped duplicates or
  repeats, and up to three named failures.

## Limits

- Prepared managed copies of a rejected batch are not deleted; the catalog is
  what stays unchanged. Reusing them would require a cleanup pass that could
  remove a copy another process is writing.
- Content identity is the source file's bytes. A re-exported file with different
  bytes (for example a re-rendered sample) is a new sound, not a duplicate.
- This is not a claim that a bulk import has been qualified on a clean Mac with
  a legally usable golden corpus; that gate stays with issue #8.
