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


# Dense controls that shipped with a fixed box below the audited touch minimum.
# control, file, the markers that identify its call sites, and the pre-fix frame.
DENSE_CONTROLS = (
    ('tonicPower', 'Sources/PerformanceControls.swift', ('Tonic Pad power',), 'frame(width:38,height:46)'),
    ('tonicPatchLock', 'Sources/PerformanceControls.swift', ('Tonic Pad Patch Lock',), 'frame(width:40,height:46)'),
    ('mixerSoundSettings', 'Sources/PerformanceControls.swift', ('Sound \\(index+1) settings',), 'frame(width: 34, height: 45)'),
    ('midiEffectBypass', 'Sources/PerformanceControls.swift', ('MIDI effect bypass',), 'frame(width: 34, height: 49)'),
    ('audioEffectBypass', 'Sources/PerformanceControls.swift', ('effect \\(slot+1) bypass',), 'frame(width: 36, height: 49)'),
    ('metronome', 'Sources/StageKeysApp.swift', ('accessibilityLabel("Metronome")',), 'frame(width: 38, height: 44)'),
    ('countIn', 'Sources/StageKeysApp.swift', ('Metronome Count In',), 'frame(width: 34, height: 44)'),
    ('importSounds', 'Sources/StageKeysApp.swift', ('Import Sounds',), 'frame(width:30,height:36)'),
    ('mainMenu', 'Sources/StageKeysApp.swift', ('Main Menu',), 'frame(width:40,height:36)'),
    ('midiLearnClose', 'Sources/MIDIControlLearnView.swift', ('Close MIDI Learn',), 'frame(width: 30,height: 30)'),
    ('librarySort', 'Sources/SoundBrowser.swift', ('Sort descending',), 'frame(width:30,height:42)'),
    ('numberStepper', 'Sources/SoundSettingsControls.swift', ('Decrease \\(title)', 'Increase \\(title)'),
     'frame(width:36,height:42)'),
)


def check_dense_targets(source: Path, errors: list) -> None:
    """Every dense control must take its box from the audited dense targets.

    These twelve shipped at 30-40 pt wide (and some at 30-42 pt high): all below
    the 44 pt touch minimum, all clearing the 28 pt pointer one. Asserting the
    constants keeps the split (44 touch / shipped pointer) in StageA11y.swift, so
    a view cannot quietly return to a literal that only suits a mouse.
    """
    record = (source / 'Sources/StageA11y.swift').read_text()
    body = re.search(r'enum DenseControl: String, CaseIterable \{(.*?)\n    \}', record, re.S)
    if not body:
        errors.append('Sources/StageA11y.swift has no DenseControl record to audit')
        return
    declared = set()
    for line in body.group(1).splitlines():
        line = line.strip()
        if line.startswith('case ') and ':' not in line:
            declared.update(name.strip() for name in line[5:].split(','))
    audited = {name for name, _, _, _ in DENSE_CONTROLS}
    for missing in sorted(declared - audited):
        errors.append(f'StageA11y.DenseControl.{missing} has no audited call site in this gate')
    for stray in sorted(audited - declared):
        errors.append(f'the gate audits {stray!r}, which StageA11y.DenseControl no longer declares')
    for name, name_file, markers, shipped in DENSE_CONTROLS:
        path = source / name_file
        if not path.exists():
            errors.append(f'{name_file} is missing, so {name!r} cannot be audited')
            continue
        text = path.read_text()
        lines = text.splitlines()
        sized = {index for index, line in enumerate(lines)
                 if f'StageA11y.denseWidth(.{name})' in line and
                 f'StageA11y.denseHeight(.{name})' in line}
        if not sized:
            errors.append(f'{name_file} does not render {name!r} through '
                          'StageA11y.denseWidth and .denseHeight')
        for marker in markers:
            hits = [index for index, line in enumerate(lines) if marker in line]
            if not hits:
                errors.append(f'{name_file} no longer contains the {name!r} control ({marker})')
            elif not any(abs(hit - index) <= 2 for hit in hits for index in sized):
                errors.append(f'the {name!r} control ({marker}) is not sized from '
                              'StageA11y.denseWidth/.denseHeight')
        if shipped in text:
            errors.append(f'{name_file} still uses the pre-fix {shipped} for {name!r} '
                          'instead of the audited target')


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
    if not re.search(r'frame\(width: workspaceButtonBox, height: workspaceButtonBox\)', body):
        errors.append('workspaceButtons does not apply the audited workspaceButtonBox')
    for label in WORKSPACE_CONTROLS:
        lines = [line for line in body.splitlines() if label in line]
        if not lines:
            errors.append(f'workspaceButtons no longer contains the {label!r} control')
        elif not all('workspaceButtonBox' in line for line in lines):
            errors.append(f'{label!r} is not sized from workspaceButtonBox')
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
    check_dense_targets(source, errors)

    if errors:
        for error in errors:
            print('FAIL:', error)
        return 1
    print(f'PASS: {len(sources)} sources hold the {MINIMUM_TEXT_SIZE} pt floor, '
          f'the palette has one definition and {len(EXCEPTIONS)} documented exception')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(Path(__file__).resolve().parents[1]))
