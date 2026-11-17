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
- **The live session is not silently replaced.** `PerformanceStore.recoverPreviousSetlist` always
  restores the file. It replaces the live performance only when the recovered document is the
  setlist currently being performed; otherwise the next autosave would immediately write the
  damaged in-memory state back over the recovered file. Recovery of a currently performed setlist
  reuses the existing key-change path: resource admission (`prepareSetlistActivation`), Panic,
  `applyPatch`, Tonic recall and the performed tempo/click clock.

## Behaviour and limits

- One previous copy per document, replaced each time the primary changes. It is a rotation copy,
  not a version history. Preserved unreadable copies use a unique file name per save, so repeated
  saves over an unreadable document accumulate files until the user removes them.
- Recovering the setlist being performed replaces the live document with the recovered one. The
  superseded library bytes stay on disk, and the separate active-session file is not modified by
  recovery, but unsaved in-memory edits made after the last save are discarded by that reload —
  which is the meaning of restoring the previous copy.
- Rotation writes at most the same bytes the primary already holds, and both writes stay inside the
  existing 64 MB per-document limit. Recovery needs free disk space for the retained copy.
- The library was already documented as "access serially on one executor"; rotation does not add
  locking and assumes the same serialized access as every other `SetlistLibrary` call.
- Recovery restores document bytes only. It does not re-admit missing samples or Audio Units by
  itself; the usual `prepareSetlistActivation` admission still applies when the recovered document
  is opened. A rejected activation leaves the recovered file in place and the live performance
  unchanged.
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
7. the existing capacity, trash, symlink and invalid-write checks still hold (the capacity fill now
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
