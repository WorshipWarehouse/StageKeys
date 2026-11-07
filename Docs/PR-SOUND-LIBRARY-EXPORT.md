# PR — independent sound exports into the local library

Audit record for the sound half of #114's export requirement. **This change does not close #114 or any other issue.**

## Why

#114 asks that patch and sound exports become immutable independent copies in the user library, that later setlist edits cannot mutate them, and that re-export or overwrite be explicit. The patch half landed first. The sound half was recorded as outstanding in `Docs/SETLIST-SHARING.md`, even though `PerformanceStore.saveSoundToLibrary` already existed: it had no user-facing entry point, no library-level export API, and no regression coverage for independence or refusal.

## What changes

- `SoundLibrary.exportSound(_:name:)` appends one `LibrarySound` to `sound-library.json`. The entry and its layer receive fresh identities, the name is trimmed and bounded to 1–200 characters, and ordinary sound imports and exports append under the same exclusive library lock.
- The export takes no identity parameter, so every call allocates a new entry. Overwriting remains an explicit library action; there is no path by which an export replaces an existing entry.
- `PerformanceStore.saveSoundToLibrary` now captures hosted Audio Unit state, validates the layer through the same `Setlist.validate()` path a save uses, writes through `SoundLibrary.exportSound`, refreshes library content issues, and reports whether the entry is present afterwards.
- `SoundEditor` gains **Save Sound to Library** plus an inline confirmation, so the action is reachable from the per-sound settings sheet used by both the wide sidebar and compact layouts.
- `Tests/SoundLibraryTests.swift` (already in the default gate) covers the new path.
- `Docs/SETLIST-SHARING.md` documents the behaviour and no longer lists sound export as outstanding.

## Acceptance mapping for this slice

| Acceptance item | Status in this change |
| --- | --- |
| Sound exports as immutable independent copies in the user library | Implemented. The entry stores the layer value, not a reference to the patch, and the copy gets fresh identities. |
| Later setlist edits must not mutate the export | Asserted: the test edits the source layer's name, gain, pan and key range after export and reloads the entry unchanged. |
| Re-export and overwrite must be explicit | Export always allocates a new identity. Overwriting is only reachable through the existing explicit library write path. |
| Refusal leaves the library untouched | A blank name is refused before the write, and the entry count is asserted unchanged. |
| Stable identities | The exported layer and entry identifiers are new; the source layer keeps its own identity. |
| Patch exports | Implemented separately in the companion change; unaffected here. |
| Clean Mac/iPad round-trip | Not claimed. No physical device was available. |

## Verification

- macOS CI is the authoritative check for this change; the result on the head commit is reported in the pull request.
- The authoring checkout is Linux without `xcrun`/`swiftc`, so local verification is limited to diff review, `git diff --check`, brace/parenthesis balance and a placeholder scan. No local build or test result is claimed.
- Targeted suite on macOS: `python3 Tests/run-local-library.py . /private/tmp/stagekeys-sound-export`.
- Not exercised: the button in a running app, VoiceOver behaviour for it, and any physical device behaviour.

## Risk

The change adds one library write path and one editor button. It does not alter activation, the audio graph, the share package format, the personal sound pack format, or import planning. The stored entry is an ordinary `LibrarySound`, so existing validation, size limits and browsing behaviour apply unchanged.
