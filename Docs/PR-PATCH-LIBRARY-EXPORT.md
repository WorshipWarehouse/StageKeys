# PR: independent patch exports into the local library (#114)

Audit-only change for [#114](https://github.com/WorshipWarehouse/StageKeys/issues/114). It does **not** close #114 or any other issue, and it does not claim the whole issue is complete.

## Why

The issue's acceptance material asks for patch and sound exports as immutable independent copies in the user library with explicit re-export/overwrite. `Docs/SETLIST-SHARING.md` recorded that item as outstanding: portable packages and library copies of whole setlists existed, but a single patch could only be duplicated inside the current setlist. This PR implements the patch half of that item and leaves the sound-export half explicitly open.

## What changes

- `SetlistLibrary.exportPatch(_:name:)` writes one patch as its own one-patch library document. The copy is built with `Patch.duplicate()`, so patch, layer and snapshot identities are new while authored settings and internal references are preserved. Document names are trimmed and bounded to 1–200 characters. Setlist-level MIDI CC assignments are not copied, because they belong to the source document.
- `PerformanceStore.exportCurrentPatchToLibrary()` saves the active patch through the library and reports the result. It does not save the current setlist, does not activate anything, does not touch `pluginState`, and does not restart audio.
- Patch menu gains **Save Patch to Library**.
- No new test file: `Tests/SetlistShareTests.swift` is already compiled and gated by `Tests/test-library.sh`.

Re-export never overwrites. `exportPatch` takes no identity parameter, so every call goes through `SetlistLibrary.save(_:id: nil)` and allocates a new document ID. Explicit overwrite remains `SetlistLibrary.save(_:id:)` and the existing library UI that uses it. A library at its 128-setlist capacity refuses the export through the existing `.full` error instead of evicting anything.

## Acceptance mapping for this slice

| Acceptance item | Status after this PR |
| --- | --- |
| Stable identities across duplicate/export/import | Patch export assigns fresh identities inside the copy and leaves the source untouched, matching the existing `duplicate()` conventions. New assertions cover patch, layer and snapshot identity separation. |
| Patch exports as immutable independent copies in the user library | Implemented through the library document model. A later edit to the source setlist cannot change the export; a repeated export creates a second document. |
| Explicit re-export/overwrite | No implicit overwrite path exists for exports. Overwriting is only reachable through the explicit identity-taking library API. |
| Sound exports as immutable independent copies | **Not implemented here.** Personal native sound packs remain a separate format. |
| Portable package/link/deep-link import, dependency and collision plans | Already implemented on `main` by #152; unchanged by this PR. |
| Clean Mac/iPad round-trip | Not claimed. No physical device was available. |

## Verification

- Inspected `git diff` and the changed call sites.
- **Not compiled and not executed.** This checkout is Linux; `Tests/test-library.sh` and `Tests/run-local-library.py` require `xcrun`/`swiftc` and the macOS frameworks used by the app. No Swift toolchain exists in this environment, so no build, test or runtime result is claimed.
- Intended macOS command for the reviewer:

  ```
  python3 Tests/run-local-library.py . /private/tmp/stagekeys-patch-export
  ```

  Expected: `SetlistShareTests` prints its PASS line and exits 0 with the new patch-export assertions included.
- Not exercised: the new patch-menu item in either app target, VoiceOver or accessibility labels for it, and any physical Mac/iPad behaviour.

## Risk

The change only adds a library write path and one menu item. It does not alter activation, audio graph, package format, checksum or import planning. The exported document is an ordinary `Setlist` with one patch, so existing validation, size and capacity limits apply unchanged.
