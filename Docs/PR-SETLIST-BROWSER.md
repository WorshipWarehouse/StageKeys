# PR audit — setlist browser history and clean-install round-trip checks

This record covers one slice of [#114](https://github.com/WorshipWarehouse/StageKeys/issues/114). It does not close the issue, and it does not claim the whole acceptance list.

## Scope

The issue asks for "recent/search/sort browsing" and for round-trip tests between clean installs, older schemas, missing dependencies, duplicate imports, interrupted writes and malformed packages. Before this change the browser could search and sort by name or modification date, but `SetlistBrowserOrder` had no last-opened history and its own comment recorded that modification time is not last-opened history. The share suite imported into an empty library root once and covered older schema versions, missing dependencies, collisions and malformed packages, but did not repeat an import or list an interrupted write.

## What changed

- `SetlistRecents` is a bounded (20), de-duplicated, device-local list stored in `setlist-recents.json`. It is a separate file so library documents keep their schema, and a missing, oversized or damaged history reads as empty instead of blocking the browser.
- `SetlistBrowserOrder.recent` sorts matched entries by recorded history first, then by saved modification date and id. `updated` and `name` keep their previous behaviour, and search applies to every order.
- `PerformanceStore` publishes `recentSetlistIDs`, loads the history at launch, records a setlist after a successful open, create or **Save and Load** import, and removes an entry when the setlist moves to Trash. Persistence failures are ignored: the history is advisory and never blocks opening a setlist.
- The browser defaults to **Recently Opened** and passes the published history to the projection. The existing **Recently Updated** and **Name A–Z** options are unchanged.
- **Clear History** in the browser header and **Remove from Recently Opened** in an entry's options menu edit only the history file. Neither action renames, moves, activates or deletes a setlist, and clearing an empty history is a no-op.
- `Tests/SetlistShareTests.swift` imports the same package twice into one empty library root, asserting a second independent copy with fresh conflicting identities, and lists a truncated document so the issue is reported while the intact entry still loads.
- `Tests/SetlistTemplateTests.swift` covers recent ordering, search interaction, capacity, de-duplication, removal and damaged-file tolerance. `Tests/StoreTests.swift` covers replay through the store, removal on Trash, clearing or forgetting history without changing the saved setlists, and persistence of a cleared history.

## Acceptance mapping for this slice

| Acceptance item | Status here |
| --- | --- |
| Create-from-scratch and create-from-template | Already implemented; unchanged. Covered by `SetlistTemplateTests`. |
| Recent/search/sort browsing | **Completed.** Last-opened ordering added; search and the existing sort orders unchanged. |
| Duplicate, rename, recoverable delete and load | Already implemented; unchanged. Covered by `StoreTests`. |
| Clean-install round-trip, duplicate imports, interrupted writes | **Deterministic coverage added.** Physical Mac/iPad qualification is still not claimed. |
| Older schema, missing samples/plugins, malicious packages | Already covered by `SetlistShareTests`; unchanged. |
| Patch/sound library exports | Separate PR, not part of this branch. |

## Verification

`Tests/SetlistTemplateTests.swift`, `Tests/SetlistShareTests.swift` and `Tests/StoreTests.swift` are all in the default library gate (`Tests/test-library.sh`), so no new test target or registration was needed. The checking command on macOS is:

```
python3 Tests/run-local-library.py . /private/tmp/stagekeys-browser
```

The authoring environment was a Linux checkout without `xcrun`/`swiftc`. Local verification was limited to a full diff review, `git diff --check`, brace/parenthesis balance and a placeholder scan. No local build or test result is claimed; CI results are reported in the pull request.

## Limits

- The history is not shared, synced or migrated; it is a per-device convenience.
- No physical Mac or iPad round-trip, native UI interaction, VoiceOver pass or audible stage check is claimed.
