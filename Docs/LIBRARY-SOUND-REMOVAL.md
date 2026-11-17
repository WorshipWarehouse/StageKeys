# Removing an imported sound from My Sounds

Refs #17. Scope: one shipped library-management action — remove a user-imported sound from
**My Sounds** — plus the catalog operation behind it. This is not optional-library
install/upgrade and not a tag/sort change.

## The gap

StageKeys let users import sounds (`Import Sounds → Instrument File`, `Sampler Folder`, MainStage
conversion, sound packs) and then browse, rate, tag and add them to modules. Nothing could remove
one again:

- `PerformanceStore.removeSound(_:)` empties a **patch layer**; it does not touch the catalog.
- The library browser's row menu offered Recommended / Note Range / Complexity only.
- `SoundLibrary` had `commitImport`, `append`, `write`, `exportSound` and `recoverPrevious`, but no
  delete.

So a mis-picked file, a duplicate import or a sound the user no longer wants stayed in `My Sounds`
for the life of the install, counted in the import window, and appeared in every patch's browser.
Issue #17's remaining work explicitly lists install/remove workflows "without silently breaking
existing setlists".

## What changed

- **`SoundLibrary.delete(id:)`.** Removes exactly one catalog entry under the existing exclusive
  write lock, returns the removed entry, and throws `SoundLibrary.EditFailure.unknownSound` when the
  id is absent. It reuses `writeUnlocked`, so the catalog still validates before publish and keeps
  its single validated previous copy through `RecoverableSessionFile.write`.
- **Managed bytes are kept.** The preset/sample files in `Imported Sounds/` stay on disk. Saved
  patches, setlists, snapshots and setlist shares reference a sound by its managed file name, so
  deleting the bytes on removal would silently break saved work — exactly what #17 forbids. The
  removed entry can be restored by importing the sound again.
- **`PerformanceStore.removeLibrarySound(_:)`.** Refuses while an import is running, refuses ids
  that are not in the catalog, and refuses entries whose collection is not `My Sounds` (bundled
  Sunday content and optional-library installs are installed content, not user imports). On success
  it re-reads the catalog, refreshes missing-content state and reports what happened.
- **Browser action.** `SoundBrowser`'s row context menu gains **Remove from My Sounds** for
  `My Sounds` entries only, with `role: .destructive`. Because the browser is a modal sheet, the
  outcome is shown in a dismissible notice bar above the footer instead of relying on the store's
  message, which would appear behind the sheet.

No file-format, tag, rating, patch, setlist, snapshot or audio change. No migration.

## Behaviour and limits

- Removal is catalog-only. Reclaiming disk space is not part of this action; an orphaned managed
  file is still there for any saved patch that uses it.
- The catalog's previous copy means an accidental removal is recoverable with the existing
  **Recover Previous Sound Catalog** action in Settings or the browser's catalog error state — until
  the next catalog write rotates it.
- Personal ratings keyed by the entry id are not deleted; re-importing a folder sound reuses its
  digest id and therefore shows its previous rating. This is deliberate: the rating belongs to the
  sound, not to the catalog row.
- Bundled/optional-library entries cannot be removed from this menu. Their install/version/remove
  workflow (and physical-device qualification) remains open on #17.
- Removal does not change a module that is currently playing the sound; layers own their settings.

## Verification

- `Tests/SoundLibraryTests` (default library gate): removing one entry keeps the other entries and
  the managed file byte-identical, returns the removed entry, throws `unknownSound` and leaves the
  catalog unchanged for a missing/duplicate id, and the previous catalog still contains the removed
  sound so `recoverPrevious()` restores it.
- `Tests/LibraryRepairTests` (default library gate): through `PerformanceStore` with a generated WAV,
  removal drops the entry from `librarySounds` and the on-disk catalog, clears its missing-content
  state, keeps the managed file and the saved session bytes identical, refuses a second removal and
  refuses an entry that is not in `My Sounds`.

Both programs fail to compile without the new API, which is the pre-fix state: no removal path
existed, so the regression is necessarily new-behaviour coverage rather than a reproduction of a
wrong value.

```bash
python3 Tests/test-library-gate.py
python3 Tests/test-local-library-runner.py
Tests/test-library.sh SoundLibraryTests LibraryRepairTests      # macOS
python3 Tests/run-local-library.py . /private/tmp/stagekeys-removal SoundLibraryTests LibraryRepairTests
```

## Not verified

- Authored on Linux with no Xcode, Apple SDKs or Swift toolchain; compilation and test execution are
  the hosted macOS/iOS Simulator CI results for this branch.
- The new menu item and notice bar were not viewed at any window size. No screenshot is included
  because the app cannot run in this workspace.
- Physical iPad/iPhone layout, VoiceOver order for the new menu/dismiss controls and a real
  user-supplied preset removal remain unqualified.
