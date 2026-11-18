# Snapshot edit undo

Capturing a snapshot into a populated slot, and clearing a populated slot, both
replace what was stored there. Before this change the replacement was immediate
and final: a named slot with notes, a custom transition and a captured mix could
be overwritten by a stray capture or cleared by a context-menu action with no way
back. The manual audit for #16 asks for overwrite warning/undo on the snapshot
strip.

## Behavior

- `PerformanceStore.snapshotUndo` holds the slot the last destructive edit
  replaced, its index, and the user-facing action it came from.
- `captureSnapshot(_:)` records the replaced slot only when that slot was
  populated. Capturing into an empty slot has nothing to restore and clears any
  older undo, so Undo always refers to the immediately preceding edit.
- `clearSnapshot(_:)` records the populated slot it replaced in the same way.
- `undoSnapshotChange()` writes the recorded slot back at its index and saves.
  The undo is consumed whether or not it applied.
- The undo is bound to the patch that recorded it. `choose(_:)` clears it, and
  `undoSnapshotChange()` refuses an entry whose `patchID` is not the current
  patch, so a stale undo can never write another patch's snapshot into the
  document now on screen.
- The snapshot strip shows **Undo Capture over Snapshot N** or **Undo Clear
  Snapshot N** next to the capture menu while an undo is available, with the
  same text as its accessibility label and help.

## Limits

- This is one step. A second destructive edit replaces the undo; there is no
  history stack.
- Reordering a slot (**Move Left**) and editing a slot (**Customize…**) are not
  recorded for undo.
- The undo lives in memory only and is not written to the session, so it is not
  offered after relaunch.
- Recalling a snapshot is unaffected: the undo restores stored snapshot content,
  it does not re-run a recall or change the active mix until the user recalls the
  restored slot.
- The strip was not viewed in a running app from the implementation workspace.

New snapshots retain a compact instrument-kind/name token and Audio Unit component identity for state ownership. They do not copy native sampler maps or private conversion metadata into every scene. Legacy snapshots without an identity retain their documented compatibility behavior; no new schema version is required for the optional identity.

A successful whole-document activation (local open/new, file/share import or previous-copy recovery) also clears the pending Undo, even when the loaded patch retains the same UUID. Rejected activation preserves the current document and its Undo. Generated regressions reproduce same-identity import and cover rejected/successful recovery.

Changing a sound source invalidates Undo before updating snapshot processing, so old sound settings cannot be restored over a replacement. Undoing an edit to another slot leaves its currently recalled snapshot and in-flight transition running. AU recall preflight checks component ownership before requiring a loaded unit; state belonging to a replaced component is skipped, while matching state still requires readiness.

Replacing an effect kind also invalidates pending snapshot Undo before updating existing scenes, so a restored cleared slot cannot reinstall the superseded processor. Parameter edits of the same processor retain their existing scene behavior.
