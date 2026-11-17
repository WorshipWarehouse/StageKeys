#!/usr/bin/env python3
"""Fail when a reserved-CC MIDI-learn attempt can unlearn the target.

The learn handler called clearMIDILearn(target) before asking
MIDIControllerRules.assigning whether the incoming CC is reserved. A sustain
pedal press (CC 64) or the mod wheel (CC 1) while the learn sheet was listening
therefore removed the target's existing assignment, reported nothing and left
the change to be persisted by the next save. The refusal must be decided from
the pure rules first.
"""
from pathlib import Path

BLOCK = 'if let target = learningTarget ?? learning.map({ MIDIControlTarget.soundLevel($0) }) {'


def main(source: Path) -> int:
    store = (source / 'Sources/Store.swift').read_text()
    test = (source / 'Tests/PlugAndPlayTests.swift').read_text()
    workflow = (source / '.github/workflows/distribution.yml').read_text()
    errors = []

    start = store.find(BLOCK)
    if start < 0:
        errors.append('the MIDI learn handler no longer has the expected shape')
    else:
        window = store[start:start + 1600]
        learned = window.find('let learned=MIDIControllerRules.assigning')
        cleared = window.find('clearMIDILearn(target,saveChanges:false)')
        if learned < 0 or cleared < 0:
            errors.append('the learn handler does not compute the rules or clear the target')
        elif cleared < learned:
            errors.append('a reserved learn still clears the target before it is refused')
        if 'message = "CC \\(cc) keeps its fixed route' not in window:
            errors.append('a refused reserved learn does not explain the fixed route')

    if '"A reserved CC must not unlearn the listening target"' not in test:
        errors.append('no regression pins that a reserved learn keeps the assignment')
    if '"A refused learn explains the reserved route"' not in test:
        errors.append('no regression pins the refusal message')
    if 'Tests/test-midi-learn-reserved.py' not in workflow:
        errors.append('the gate is not run by the processing job')

    if errors:
        for error in errors:
            print('FAIL:', error)
        return 1
    print('PASS: a reserved MIDI-learn attempt is refused before it can unlearn the target')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(Path(__file__).resolve().parents[1]))
