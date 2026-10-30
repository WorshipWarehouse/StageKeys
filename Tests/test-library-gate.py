#!/usr/bin/env python3
"""Fail when a test program is neither in the default gate nor documented on demand."""
import re
from pathlib import Path

# Hardware, private content or a specific installed third-party Audio Unit. The
# reason is checked against the table in Docs/LOCAL-VERIFICATION.md, so the
# classification cannot drift away from what is documented.
ON_DEMAND = {
    'AudioDeviceTests': 'enumerates and guards a live output device',
    'LivePatchContentTests': 'requires live streaming through the audio device',
    'RealtimePianoTests': 'requires live audio and a private piano preset',
    'CapturedSoundPlaybackTests': 'requires a private converted-capture library',
    'FeltPianoFidelityTests': 'requires the private Felt Piano source and samples',
    'LivePianoFidelityTests': 'requires private piano libraries and live streaming',
    'OutputHeadroomTests': 'requires private converted library sounds',
    'SoundIdentityTests': 'requires private converted library sounds',
    'AudioUnitTests': 'requires an installed third-party Audio Unit such as OB-Xd',
}
SCRATCH_ARGUMENT_TESTS = {'AudioGraphTests', 'ExternalAudioTests',
                          'SamplerInterchangeTests', 'SetlistLibraryTests'}


def main(source: Path) -> int:
    shell = (source / 'Tests/test-library.sh').read_text()
    swift_match = re.search(r'else tests=\((.*?)\); fi', shell, re.S)
    native_match = re.search(r'^for test in ([A-Za-z0-9_ ]+); do', shell, re.M)
    sanitizer_match = re.search(r'^for test in ([A-Za-z0-9_ ]+); do',
                                (source / 'Tests/test-reverb.sh').read_text(), re.M)
    if not swift_match or not native_match or not sanitizer_match:
        print('FAIL: cannot read the default Swift/C or sanitizer gate')
        return 1
    swift, native = swift_match.group(1).split(), native_match.group(1).split()
    sanitizer = sanitizer_match.group(1).split()
    documentation = (source / 'Docs/LOCAL-VERIFICATION.md').read_text()
    runner = (source / 'Tests/run-local-library.py').read_text()
    swift_files = {path.stem for path in (source / 'Tests').glob('*.swift')} - {'FixtureSupport'}
    native_files = {path.stem for path in (source / 'Tests').glob('*.c')}
    errors = []

    for label, names, files, suffix in [('Swift', swift, swift_files, '.swift'),
                                        ('C', native, native_files, '.c'),
                                        ('Sanitizer', sanitizer, native_files, '.c')]:
        duplicates = sorted({name for name in names if names.count(name) > 1})
        if duplicates:
            errors.append(f'{label} gate lists duplicates: {", ".join(duplicates)}')
        for name in names:
            if name not in files:
                errors.append(f'{label} gate lists missing Tests/{name}{suffix}')

    gated = set(swift) | set(native)
    for name in sorted(SCRATCH_ARGUMENT_TESTS):
        if name not in swift:
            errors.append(f'{name} takes a scratch path but is not in the default gate')
        if name not in shell:
            errors.append(f'{name} has no scratch-path case in Tests/test-library.sh')
        if name not in runner:
            errors.append(f'{name} has no scratch-path handling in Tests/run-local-library.py')

    for name in sorted(swift_files):
        if name not in gated and name not in ON_DEMAND:
            errors.append(f'{name} is neither in the default gate nor documented as on demand')
    for name in sorted(native_files - set(native) - set(sanitizer)):
        errors.append(f'{name} is in neither the library gate nor the sanitizer gate')

    for name, reason in sorted(ON_DEMAND.items()):
        if name in gated:
            errors.append(f'{name} is documented as on demand but also gated')
        if name not in swift_files and name not in native_files:
            errors.append(f'{name} is documented as on demand but has no test program')
        if not reason.strip():
            errors.append(f'{name} has no on-demand reason')
        if name not in documentation:
            errors.append(f'{name} is not classified in Docs/LOCAL-VERIFICATION.md')

    if errors:
        for error in errors:
            print('FAIL:', error)
        return 1
    print(f'PASS: {len(swift)} Swift programs gated, {len(native)} C programs in the library gate, '
          f'{len(sanitizer)} in the sanitizer gate, {len(ON_DEMAND)} documented as on demand')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(Path(__file__).resolve().parents[1]))
