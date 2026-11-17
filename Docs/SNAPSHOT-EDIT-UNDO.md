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
