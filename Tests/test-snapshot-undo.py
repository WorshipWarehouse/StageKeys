#!/usr/bin/env python3
"""Fail when a destructive snapshot edit cannot be undone.

Capturing over a populated snapshot slot or clearing it replaced the slot in
place, so its name, note, transition and captured mix were lost with no way
back. The store now keeps the replaced slot for one step, bound to the patch
that recorded it, and the snapshot strip offers the undo.
"""
from pathlib import Path

ACTIONS = ['action: "Clear Snapshot', 'action: "Capture over Snapshot']


def main(source: Path) -> int:
    store = (source / 'Sources/Store.swift').read_text()
    strip = (source / 'Sources/StageKeysApp.swift').read_text()
    tests = (source / 'Tests/SnapshotSlotTests.swift').read_text()
    workflow = (source / '.github/workflows/distribution.yml').read_text()
    errors = []

    if 'struct SnapshotUndo' not in store or '@Published var snapshotUndo: SnapshotUndo?' not in store:
        errors.append('the store has no published one-step snapshot undo')
    for action in ACTIONS:
        if action not in store:
            errors.append(f'the destructive edit does not record its replaced slot: {action}')
    if 'func undoSnapshotChange()' not in store or 'undo.patchID==patch.id' not in store:
        errors.append('the undo is not bound to the patch that recorded it')
    if 'snapshotUndo = nil' not in store:
        errors.append('a patch change does not clear the previous patch undo')
    if 'store.undoSnapshotChange()' not in strip:
        errors.append('the snapshot strip offers no undo action')
    if '"A patch change must drop the previous patch\'s undo"' not in tests:
        errors.append('no regression pins that a patch change drops the undo')
    if 'Undo must restore a cleared snapshot' not in tests:
        errors.append('no regression pins that a cleared snapshot can be restored')
    if 'Tests/test-snapshot-undo.py' not in workflow:
        errors.append('the gate is not run by the processing job')

    if errors:
        for error in errors:
            print('FAIL:', error)
        return 1
    print('PASS: capturing over or clearing a populated snapshot keeps a patch-bound one-step undo')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(Path(__file__).resolve().parents[1]))
