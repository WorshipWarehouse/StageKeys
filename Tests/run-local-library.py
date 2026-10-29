#!/usr/bin/env python3
"""Compile the shared test core once; run the unchanged shell gate's test bodies."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time
import uuid


def plan(source):
    text = (source / 'Tests/test-library.sh').read_text()
    sources = re.findall(r'"\$repo/(Sources/[^"\n]+\.swift)"', text)
    swift = re.search(r'else tests=\((.*?)\); fi', text)
    native = re.search(r'^for test in ([A-Za-z0-9_ ]+); do', text, re.M)
    if not sources or swift is None or native is None:
        raise ValueError('Cannot read the complete Swift/C test plan from test-library.sh')
    swift, native = swift.group(1).split(), native.group(1).split()
    for label, names in [('sources', sources), ('Swift tests', swift), ('C tests', native)]:
        if not names or len(names) != len(set(names)):
            raise ValueError('Empty or duplicate ' + label)
    return sources, swift, native


def run_command(command, env=None):
    print('+', ' '.join(map(str, command[:5])), flush=True)
    result = subprocess.run(list(map(str, command)), env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
    print(result.stdout, end='', flush=True)
    result.check_returncode()
    return result.stdout


def fixture_args(test, build, env):
    if test == 'EXSImportTests' and env.get('STAGEKEYS_EXS_FIXTURE') and env.get('STAGEKEYS_EXS_ROOT'):
        return [build / 'exs-scratch', env['STAGEKEYS_EXS_FIXTURE'], env['STAGEKEYS_EXS_ROOT']]
    return []


def execute_test(test, compile_command, executable, build, results):
    started = time.monotonic()
    record = {'test': test, 'status': 'failed', 'passed': False}
    try:
        run_command(compile_command)
        env = os.environ.copy()
        env['STAGEKEYS_DATA_DIR'] = str(build / f'data-{test}-{uuid.uuid4().hex}')
        output = run_command([executable] + fixture_args(test, build, env), env)
        skips = [line for line in output.splitlines() if line.startswith('SKIP')]
        record.update(status='skipped' if skips else 'passed', passed=None if skips else True)
        if skips:
            record['reasons'] = skips
    except (subprocess.SubprocessError, OSError) as error:
        record['error'] = str(error)
        raise
    finally:
        record['seconds'] = round(time.monotonic() - started, 3)
        results.append(record)
        (build / 'results.json').write_text(json.dumps(results, indent=2) + '\n')


def summary(build, results):
    counts = {status: sum(x['status'] == status for x in results)
              for status in ('passed', 'skipped', 'failed')}
    lines = ['## Library regression results', '',
             f"{counts['passed']} passed · {counts['skipped']} skipped · {counts['failed']} failed", '',
             'Skipped private fixtures are not exercised compatibility checks.']
    for record in results:
        if record['status'] != 'passed':
            lines.append(f"- {record['test']}: {record['status']} " +
                         '; '.join(record.get('reasons', [record.get('error', '')])))
    text = '\n'.join(lines) + '\n'
    (build / 'summary.md').write_text(text)
    print(text, flush=True)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as output:
            output.write(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('build', type=Path)
    parser.add_argument('tests', nargs='*')
    args = parser.parse_args()
    source, build = args.source.resolve(), args.build.resolve()
    if build == source or source in build.parents:
        parser.error('Choose a build directory outside the source checkout')
    sources, swift, native = plan(source)
    if args.tests:
        swift, native = args.tests, []
    if any(not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', name) for name in swift + native):
        parser.error('Test names must be simple source-file identifiers')
    build.mkdir(parents=True, exist_ok=True)
    results = []
    (build / 'results.json').write_text('[]\n')
    try:
        for name in ['Synth', 'CreamCoat']:
            run_command(['xcrun', 'clang', '-std=c11', '-O2', '-c', source / f'Sources/{name}.c', '-o', build / f'{name}.o'])
        common = ['xcrun', 'swiftc', '-DDEBUG', '-module-cache-path', build / 'modules',
                  '-import-objc-header', source / 'Sources/Bridge.h']
        run_command(common + ['-enable-testing', '-emit-library', '-emit-module', '-parse-as-library',
                    '-module-name', 'StageKeysVerificationCore'] + [source / x for x in sources] +
                    [build / 'Synth.o', build / 'CreamCoat.o', '-framework', 'CoreMIDI', '-lz',
                     '-o', build / 'libStageKeysVerificationCore.dylib', '-emit-module-path',
                     build / 'StageKeysVerificationCore.swiftmodule'])
        for test in swift:
            path = build / f'{test}.swift'
            path.write_text('@testable import StageKeysVerificationCore\n' + (source / f'Tests/{test}.swift').read_text())
            command = common + ['-parse-as-library', '-I', build, '-L', build, '-lStageKeysVerificationCore',
                       '-Xlinker', '-rpath', '-Xlinker', build, path, '-framework', 'CoreMIDI', '-lz', '-o', build / test]
            execute_test(test, command, build / test, build, results)
        for test in native:
            command = ['xcrun', 'clang', '-I', source / 'Sources', '-std=c11', '-O1', '-g',
                       source / f'Tests/{test}.c', build / 'Synth.o', build / 'CreamCoat.o',
                       '-framework', 'CoreMIDI', '-o', build / test]
            execute_test(test, command, build / test, build, results)
    except (subprocess.SubprocessError, OSError, ValueError):
        # Compile/setup failures must remain visible even before a test record exists.
        if not results or results[-1]['status'] != 'failed':
            results.append({'test': 'runner/setup', 'status': 'failed', 'passed': False})
            (build / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
        raise
    finally:
        summary(build, results)


if __name__ == '__main__':
    main()
