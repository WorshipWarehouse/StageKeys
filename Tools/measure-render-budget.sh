#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
if [[ $# != 1 ]]; then echo 'Usage: Tools/measure-render-budget.sh NEW-output-directory' >&2; exit 2; fi
# A fresh external directory retains compiler, machine, revision and raw evidence.
python3 - "$repo" "$1" <<'PY'
import json, platform, subprocess, sys
from pathlib import Path
repo, output = map(lambda x: Path(x).resolve(), sys.argv[1:])
if output == repo or repo in output.parents:
    raise SystemExit('Choose an output directory outside the checkout')
output.mkdir(parents=True, exist_ok=False)
def read(args):
    return subprocess.check_output(args, cwd=repo, text=True).strip()
def optional_read(args):
    result = subprocess.run(args, cwd=repo, text=True, capture_output=True)
    return result.stdout.strip() if result.returncode == 0 else None
metadata = {
    'revision': read(['git', 'rev-parse', 'HEAD']),
    'dirty': bool(read(['git', 'status', '--porcelain'])),
    'os': platform.platform(), 'architecture': platform.machine(),
    'hardwareModel': optional_read(['sysctl', '-n', 'hw.model']),
    'compiler': read(['xcrun', 'clang', '--version']),
    'optimization': '-O2', 'audioDevice': None, 'clock': 'mach_absolute_time',
    'scope': 'Offline C stereo effects only; no sampler, AU, hardware latency or underrun measurement',
    'backgroundLoad': 'Uncontrolled; record separately for comparisons',
}
import hashlib
metadata['inputSHA256'] = {p: hashlib.sha256((repo / p).read_bytes()).hexdigest() for p in
    ['Tools/RenderBudget.c', 'Tools/measure-render-budget.sh', 'Sources/Synth.c',
     'Sources/Synth.h', 'Sources/ShimmerPitch.h', 'Sources/CreamCoat.c', 'Sources/CreamCoat.h']}
(output / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
command = ['xcrun', 'clang', '-std=c11', '-O2', '-Wall', '-Wextra', '-I', str(repo / 'Sources'),
           str(repo / 'Tools/RenderBudget.c'), str(repo / 'Sources/Synth.c'),
           str(repo / 'Sources/CreamCoat.c'), '-framework', 'CoreMIDI', '-lm',
           '-o', str(output / 'RenderBudget')]
with (output / 'build.log').open('w') as log:
    subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
with (output / 'report.json').open('w') as report:
    subprocess.run([str(output / 'RenderBudget')], stdout=report, check=True)
report = json.loads((output / 'report.json').read_text())
rows = report['rows']
assert len(rows) == 54
import math
for row in rows:
    assert 0 < row['medianMicroseconds'] <= row['p95Microseconds'] <= row['worstMicroseconds']
    assert all(math.isfinite(v) for v in row.values() if isinstance(v, float))
    assert 0 <= row['blocksOverDeadline'] <= row['measuredBlocks']
    assert row['peak'] > 0
assert len({(r['rate'], r['frames'], r['trial'], r['engaged']) for r in rows}) == 54
print(f"Recorded {len(rows)} offline measurements in {output}")
print('Performance is reported, not gated; inspect every over-deadline count and worst block.')
PY
