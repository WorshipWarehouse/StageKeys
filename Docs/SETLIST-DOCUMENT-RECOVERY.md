# Saved-setlist document recovery

Refs #20. Scope: one recoverable rotation copy for each saved setlist document in the local
setlist library, plus an explicit restore action. This is a file-level safeguard; it is not a
schema migration, an autosave/undo stack or a clean-device restore.

## The gap this closes

Every other persisted StageKeys archive already rotates and restores a validated previous copy
through `RecoverableSessionFile` (the active session, sound catalog, ratings, personal effect
presets). A saved setlist document in the local library (`Setlists/<uuid>.json`) did not:

- `SetlistLibrary.save` wrote the new bytes atomically and nothing else, so the previously saved
  document was simply replaced.
- `SetlistLibrary.list` reported an unreadable document as an orange error row in
  **Settings → Setlists** with no action beside it.

The result was a save path with no route back: a damaged, truncated or wrongly rewritten library
document was reported but not recoverable, even though every neighbouring archive was.

## What changed

- **Rotation on save.** When an existing document's bytes change, `SetlistLibrary.save` first
  decodes the old bytes with the same `Setlist.upgraded()` reader the library uses for a normal
  load. A readable document is written to `<uuid>.json.previous` (atomic, one copy, replaced on the
  next changed save). Readable bytes are never rotated over the previous copy.
- **Damaged bytes are preserved.** If the existing primary no longer decodes, its bytes are written
  to `<uuid>.json.damaged-<uuid>` instead of being rotated. A corrupt document therefore never
  becomes the "good" copy, and its bytes are still on disk for inspection.
- **Recovery is explicit and per document.** `SetlistLibrary.recoverPrevious(id:)` restores the
  previous copy only when it decodes, retains the unreadable primary beside it (the same
  `RecoverableSessionFile.restore` behaviour the session file uses) and replaces the primary
  atomically. A document without a readable previous copy throws
  `SetlistLibraryError.noPreviousCopy`.
- **The error row carries the truth.** `SetlistLibraryIssue` now records the document identity and
  whether a validated previous copy exists, so **Settings → Setlists** shows **Restore Previous
  Copy** only where it can succeed.
- **The live session is not silently replaced.** `PerformanceStore.recoverPreviousSetlist` decodes
  the previous copy through `SetlistLibrary.previous(id:)` and, for the setlist currently being
  performed, runs the existing admission (`prepareSetlistActivation`) before the file is restored.
  Publishing first would let the next autosave write the old damaged in-memory state over a
  recovered document that had never been accepted. Recovery then reuses the same key-change path:
  Panic, `applyPatch`, Tonic recall and the performed tempo/click clock, and Patch Lock refuses the
  change before any file work. An inactive document is restored without touching the live session.

## Behaviour and limits

- One previous copy per document, replaced each time the primary changes. It is a rotation copy,
  not a version history. Preserved unreadable copies use a unique file name per save, so repeated
  saves over an unreadable document accumulate files until the user removes them.
- Recovering the setlist being performed replaces the live document with the recovered one. That
  save rewrites the active session and settings and rotates their previous copies; recovering a
  document that is **not** being performed leaves the session files untouched. Unsaved in-memory
  edits made after the last save are discarded by the reload — which is the meaning of restoring the
  previous copy.
- Recovery of any document is refused while Patch Lock is on, matching every other setlist switch;
  the lock is released in the patch controls, and no bytes change while it is on.
- Rotation writes at most the same bytes the primary already holds, and both writes stay inside the
  existing 64 MB per-document limit. Recovery needs free disk space for the retained copy.
- The library was already documented as "access serially on one executor"; rotation does not add
  locking and assumes the same serialized access as every other `SetlistLibrary` call.
- Recovery restores document bytes only, and it does not re-admit missing samples or Audio Units by
  itself. For the setlist being performed, the previous copy is decoded and admitted
  (`prepareSetlistActivation`) **before** it is published over the damaged document, so a rejected
  activation leaves the damaged file and the recoverable copy exactly as they were, and the live
  performance unchanged.
- `Store.save` preserves the current setlist on most edits, so the previous copy tracks the last
  changed save rather than a fixed interval. Unchanged saves write nothing.
- The existing session-level recovery (`Docs/SESSION-RECOVERY-LIMITS.md`) still governs the active
  session file. A successful disk restore is not rolled back if a later graph activation fails.

## Verification

`Tests/SetlistLibraryTests` (already in the default library gate) now asserts:

1. a first save creates no previous copy;
2. a changed save creates one, and `hasPreviousCopy` reports it only when it decodes;
3. an unreadable document is reported with `recoverable == true` and its reason;
4. `recoverPrevious` restores the earlier document, retains
   `<uuid>.json.damaged-<uuid>`, and the restored bytes load through `load(id:)`;
5. unreadable primary bytes are preserved instead of rotated, so the previous copy still restores;
6. recovery without a previous copy throws `noPreviousCopy`;
7. `previous(id:)` decodes the rotation copy without publishing it or retaining a damaged copy, so
   admission can reject it before any bytes change, and recovery afterwards still works;
8. the existing capacity, trash, symlink and invalid-write checks still hold (the capacity fill now
   counts whatever documents the test has already created).

Commands:

```bash
python3 Tests/test-library-gate.py
python3 Tests/test-local-library-runner.py
Tests/test-library.sh SetlistLibraryTests          # macOS
python3 Tests/run-local-library.py . /private/tmp/stagekeys-setlist-recovery SetlistLibraryTests
```

## Not verified

- The Swift changes were authored on Linux without Xcode or Apple SDKs. Compilation and the
  `SetlistLibraryTests` execution above are macOS CI checks and had not run when this record was
  written.
- No macOS or iOS UI session was inspected, so the new Settings button's layout at any window size
  is unverified; it renders inside the existing issue list.
- Recovery of physically damaged files with filesystem-level failures (permissions, full disk,
  read-only volume) is limited by the same factors already documented for session recovery.
