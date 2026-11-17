# Library repair — missing samples

## Defect

A library sound can report two content issues from the import report: `.missingFile`
(the managed sound file itself is gone) and `.missingSamples` (the managed preset is
present but a sample it references cannot be read, for example after the sampler's
sample folder was moved or removed). The browser footer offered a repair action only
for `.missingFile`, so a sound in the `.missingSamples` state showed its message with
no action and stayed unavailable.

## Fix

- `LibraryContentIssue` now names its own repair (`repairTitle`) and says whether the
  repair needs a folder (`repairsWithFolder`). The missing-file repair keeps the same
  title, file picker and copy as before.
- The footer offers the repair for any content issue. `.missingFile` opens the existing
  file picker and calls `Store.relinkLibrarySound(_:from:)`. `.missingSamples` opens a
  folder picker and calls the new `Store.relinkLibrarySamples(_:from:)`.
- `Store.relinkLibrarySamples(_:from:)` re-resolves the sound's retained original preset
  (`Original Instruments/`) against the folder the user chose, through the existing
  `ExternalInstrumentRack.importPreset(_:sampleRoot:)` / `importEXS(_:sampleRoot:)`
  resolver. That resolver matches each `file-references` entry by path suffix under the
  chosen folder, copies the samples into new managed storage and rewrites the preset's
  references. The repaired preset is published only when
  `ExternalInstrumentRack.contentIssue(in:kind:)` reports no issue for it; the entry
  keeps its id, name, tags, collection, ratings and retained original.

## Behaviour

- A wrong or incomplete folder is refused by the existing resolver with its
  "Missing sample: …" message. The entry stays `.missingSamples`, the catalog bytes are
  unchanged and no partial sample copy or preset is left behind. The footer keeps
  showing the same unchanged issue message.
- Cancelling the picker changes nothing.
- The previous managed preset and its sample folder are kept after a successful repair,
  because saved patches may still reference them. A repaired sound is a new managed
  preset; the old one is never deleted by this flow.
- Ratings, the hover preview, the help text and the on-disk library formats are
  unchanged.

## Limits

- The repair copies the samples into managed storage, so it uses disk space
  proportional to the sample set and does not reference the user's folder afterwards.
- A preset with no retained original falls back to the managed preset. If its managed
  sample copies are gone, the suffix resolver cannot match the user's files and the
  repair is refused with the same message rather than publishing a partial sound.
- Only absolute `file-references` are verified by `ExternalInstrumentRack`; relative or
  opaque references are left to the sampler resolver, so this flow does not claim to
  repair them.
- The folder picker, hover preview and successful/failed repair copy were not viewed on
  macOS or iOS from this workspace.

## Verification

- `Tests/LibraryRepairTests.swift` imports a sampler preset with a missing absolute
  sample reference, removes its managed sample folder, asserts the reported
  `.missingSamples` issue, proves a wrong folder is refused without rewriting the
  catalog or setlist, then repairs with the folder that holds the sample and asserts
  the entry reports no issue, the catalog on disk names the new preset, the retained
  original and entry metadata are unchanged, the previous managed preset is kept and
  the setlist bytes are untouched.
- `Tests/test-library-gate.py` fails when a content issue has no repair action or when
  the browser does not route a folder issue to the folder picker and the sample-folder
  repair.
- Run `Tests/test-library.sh` on macOS for the full library suite.
