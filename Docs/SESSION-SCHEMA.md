# Saved-session schema

A saved StageKeys session (`setlist.json`) carries a schema version so a build can
tell three situations apart: a document it can migrate, a document it already
writes, and a document written by a newer build. `Sources/Models.swift` owns the
boundary (`SetlistSchema`), and `Sources/Store.swift` owns what the app does when
the boundary refuses a file.

## Supported versions

| Schema | Status in this build | What happens on load |
| --- | --- | --- |
| `1`, `2`, `3` | older, migratable | validated, then migrated to `4`, then loaded |
| `4` | current | validated and loaded |
| `5` and above | newer than this build | refused as a newer session; nothing is loaded and nothing is written |
| below `1` | not a schema this project ever wrote | refused as unreadable |

The oldest document this build reads is schema 1, the current one is schema 4, and
`SetlistSchema.supported` (`SetlistSchema.oldestSupported`...`SetlistSchema.current`)
is the closed range between them. The migration itself
is unchanged: each patch keeps fifteen playable slots and each snapshot's gains
and per-sound states are extended to match, so an old session opens with the same
voices, gains and snapshots it was saved with.

The saved schema is read from a version envelope before anything else is decoded,
so a newer document is refused for being newer even when it also changed the shape
of fields this build knows. Without that, such a document would fail to decode and
be reported as damage, which would make it look recoverable.

## What each outcome does

- **Current or older:** the session loads. If it came from an older schema, the
  original bytes are archived once as `setlist-v<N>-backup.json` next to the
  session before the first save in the current schema, and the normal previous-copy
  rotation applies as usual.
- **Newer than this build:** `Setlist.validate()` throws
  `SetlistError.unsupportedVersion(saved:supported:)`, which names the saved schema
  and the range this build reads. Autosave stays blocked, the message says the
  saved files were **left unchanged**, and Settings offers no Recover Previous Session
  action for it: replacing a newer session with an older copy is a downgrade, not a
  repair.
- **Unreadable (below `1`):** refused by the same typed error, but the message says
  this build does not read that schema instead of calling it newer.
- **Damaged or invalid:** still reported as `SetlistError.invalid`, so corruption
  keeps the existing recovery path.

## Limits

- There is no forward migration and no downgrade writer. A newer session can only
  be opened by a build that reads its schema.
- Recovery refuses only while the *loaded* session is a newer-schema document.
  Once StageKeys is updated and the session loads, the normal recovery flow is
  available again.
- Nothing in this boundary rewrites the refused file: the primary, the previous
  copy and any versioned archive on disk are byte-identical after a refusal.
- The boundary covers every stored setlist document this build reads: the active
  `setlist.json`, a `.json` setlist imported through Load, a setlist document
  opened as a file, and the setlists in the local library. Sealed
  `.stagekeyssetlist` share packages keep their own format and validation, and
  `settings.json`, the sound catalog, ratings and personal presets have their own
  validated archives; they are out of scope here.

## Evidence

- `Tests/SessionSchemaVersionTests.swift` builds synthetic fixtures in-test: every
  supported schema, a legacy three-slot document for schemas `1`–`3`, schemas `5`
  and `99`, schema `0`, and a damaged document with no patches. It then drives a
  `PerformanceStore` over a newer-schema session with a valid previous copy and
  asserts that recovery and autosave both leave the newer bytes intact, and over a
  damaged session and asserts that explicit recovery still restores the previous
  copy.
- `Tests/test-session-schema.py` fails when the boundary, the typed refusal, the
  recovery guard, the Settings message, the test coverage, the CHANGELOG entry or
  the gate wiring drifts.
- `Tests/SessionMigrationTests.swift` keeps the separate end-to-end migration,
  rollback and interrupted-write coverage for a schema-1 session.
