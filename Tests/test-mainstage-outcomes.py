#!/usr/bin/env python3
"""Fail when a finished MainStage import outcome can be relabelled by a later failure.

`PerformanceStore.importMainStageSamplers` closes outcomes that are still waiting
to commit when the batch throws. A duplicate is already in the catalog and a
converted channel is already published, so the failure path must not claim them:
that reported an installed channel as failed or cancelled and dropped the reason
it was skipped. The state machine now names that boundary, and the guided import
regression holds the catalog lock so the commit cannot finish.
"""
from pathlib import Path

CONTRACT = 'var awaitingCommit:Bool {self == .pending || self == .prepared}'
FORBIDDEN = '[.pending,.prepared,.duplicate]'


def main(source: Path) -> int:
    outcomes = (source / 'Sources/MainStagePatch.swift').read_text()
    store = (source / 'Sources/Store.swift').read_text()
    tests = (source / 'Tests/MainStageGuidedImportTests.swift').read_text()
    workflow = (source / '.github/workflows/distribution.yml').read_text()
    errors = []

    if CONTRACT not in outcomes:
        errors.append('MainStageChannelOutcome.State has no awaitingCommit contract '
                      'separating unfinished from already-finished outcomes')
    if FORBIDDEN in store:
        errors.append('the import failure path still rewrites duplicate outcomes')
    if 'state.awaitingCommit' not in store:
        errors.append('the import failure path does not use the awaitingCommit contract')
    if '[.duplicate,.duplicate,.needsSamples]' not in tests:
        errors.append('no regression pins the duplicate outcomes a refused commit keeps')
    if '"Already installed"' not in tests:
        errors.append('no regression pins the duplicate detail retained after a refusal')
    if 'Tests/test-mainstage-outcomes.py' not in workflow:
        errors.append('the gate is not run by the processing job')

    if errors:
        for error in errors:
            print('FAIL:', error)
        return 1
    print('PASS: only outcomes still waiting to commit are closed when an import batch fails')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(Path(__file__).resolve().parents[1]))
