#!/usr/bin/env python3
"""Fail when a text literal drops below the readable floor or the audited
palette/verification record drifts away from the code.

`Tests/StageA11yTests.swift` asserts the numbers; this source check asserts that
the views actually go through the clamped theme, and that any exception is
documented in Docs/ACCESSIBILITY.md with a reason the reviewer can read.
"""
import re
from pathlib import Path

MINIMUM_TEXT_SIZE = 11

# A deliberate exception: the file, a stable literal from the line, and why it is
# allowed below the floor. The reason must appear verbatim in the documentation,
# the same way Tests/test-library-gate.py checks its on-demand table.
EXCEPTIONS = {
    ('Sources/PerformanceControls.swift', r'C\(note/12-1)'):
        'piano octave marker is decorative and sized to the key width',
}

SIZE = re.compile(r'(?:StageTheme\.font\(|\.system\(size:\s*)(\d+(?:\.\d+)?)')
# The four release surfaces must come from StageA11y.Palette, not local literals.
DUPLICATED_PALETTE = re.compile(r'Color\(red:\s*0\.065|Color\(red:\s*0\.14,|'
                                r'Color\(red:\s*0\.23,|Color\(red:\s*0\.64,')


WORKSPACE_CONTROLS = ('Sustain pedal', 'Edit keyboard layers', 'Show keyboard ranges')


def check_workspace_targets(source: Path, errors: list) -> None:
    """The workspace strip must size its icon buttons from the audited target.

    Those three buttons shipped as a literal 30 x 28 box: exactly the pointer
    minimum and 14 pt short of the touch minimum. Asserting the constant instead
    of the number keeps the split (44 touch / 30 pointer) in one place.
    """
    path = source / 'Sources/StageKeysApp.swift'
    text = path.read_text()
    block = re.search(r'private var workspaceButtons: some View \{.*?\n    \}', text, re.S)
    if not block:
        errors.append('Sources/StageKeysApp.swift has no workspaceButtons view to audit')
        return
    body = block.group(0)
    if 'StageA11y.workspaceButtonTarget' not in text:
        errors.append('workspaceButtons does not size its buttons from StageA11y.workspaceButtonTarget')
    # The audited target is the whole styled footprint, not an inner frame that the
    # style's padding then grows past, so each button passes it to the style.
    if not re.search(r'frame\(width: fixedSize, height: fixedSize\)', text):
        errors.append('StageButtonStyle does not apply a fixed button footprint')
    for label in WORKSPACE_CONTROLS:
        lines = [line for line in body.splitlines() if label in line]
        if not lines:
            errors.append(f'workspaceButtons no longer contains the {label!r} control')
        elif not all('fixedSize: workspaceButtonTarget' in line for line in lines):
            errors.append(f'{label!r} is not sized from the audited workspaceButtonTarget')
    literal = re.search(r'frame\(width: (\d+), height: (\d+)\)', body)
    if literal:
        errors.append('workspaceButtons still uses a literal '
                      f'{literal.group(1)} x {literal.group(2)} box instead of the audited target')


def main(source: Path) -> int:
    errors = []
    docs_path = source / 'Docs/ACCESSIBILITY.md'
    docs = docs_path.read_text() if docs_path.exists() else ''
    if not docs:
        errors.append('Docs/ACCESSIBILITY.md is missing; the audit has no record')

    sources = sorted((source / 'Sources').glob('*.swift'))
    if not sources:
        errors.append('no Sources/*.swift found')
    for path in sources:
        name = f'Sources/{path.name}'
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if DUPLICATED_PALETTE.search(line):
                errors.append(f'{name}:{number} defines a release palette colour outside StageA11y.Palette')
            if 'Text(' not in line:
                continue
            for match in SIZE.finditer(line):
                size = float(match.group(1))
                if size >= MINIMUM_TEXT_SIZE:
                    continue
                exception = next(((key, reason) for key, reason in EXCEPTIONS.items()
                                  if key[0] == name and key[1] in line), None)
                if exception is None:
                    errors.append(f'{name}:{number} renders Text at {size:g} pt, '
                                  f'below the {MINIMUM_TEXT_SIZE} pt readable floor')
                elif exception[1] not in docs:
                    errors.append(f'{name}:{number} exception is not documented: {exception[1]}')
    for (name, marker), reason in sorted(EXCEPTIONS.items()):
        if not (source / name).exists():
            errors.append(f'{name} exception points at a missing file')
        elif marker not in (source / name).read_text():
            errors.append(f'{name} no longer contains the exempted line "{marker}"')
        if reason not in docs:
            errors.append(f'exception reason is not in Docs/ACCESSIBILITY.md: {reason}')

    theme = (source / 'Sources/StageKeysApp.swift').read_text()
    if 'StageA11y.Palette' not in theme:
        errors.append('StageTheme does not build its colours from StageA11y.Palette')
    font = re.search(r'static func font\(_ size: CGFloat.*?\n    \}', theme, re.S)
    if not font or 'StageA11y.fontSize(' not in font.group(0):
        errors.append('StageTheme.font does not clamp sizes through StageA11y.fontSize')
    for absent in ('static let base = color(StageA11y.Palette.base)',
                   'static let panel = color(StageA11y.Palette.panel)',
                   'static let raised = color(StageA11y.Palette.raised)',
                   'static let selected = color(StageA11y.Palette.selected)'):
        if absent not in theme:
            errors.append(f'StageTheme is missing {absent}')

    shell = (source / 'Tests/test-library.sh').read_text()
    if 'Sources/StageA11y.swift' not in shell:
        errors.append('Tests/test-library.sh does not compile Sources/StageA11y.swift')
    if 'StageA11yTests' not in shell:
        errors.append('Tests/test-library.sh does not run StageA11yTests')
    if not (source / 'Sources/StageA11y.swift').exists():
        errors.append('Sources/StageA11y.swift is missing')
    if not (source / 'Tests/StageA11yTests.swift').exists():
        errors.append('Tests/StageA11yTests.swift is missing')

    check_workspace_targets(source, errors)

    if errors:
        for error in errors:
            print('FAIL:', error)
        return 1
    print(f'PASS: {len(sources)} sources hold the {MINIMUM_TEXT_SIZE} pt floor, '
          f'the palette has one definition and {len(EXCEPTIONS)} documented exception')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(Path(__file__).resolve().parents[1]))
