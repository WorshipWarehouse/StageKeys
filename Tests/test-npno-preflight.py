#!/usr/bin/env python3
"""Fail when the bounded .npno inspection contract, its limits or its refusals drift."""
import re
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
errors = []


def fail(message):
    errors.append(message)


LIMITS = ['maximumFileBytes', 'maximumUnclassifiedBytes', 'maximumReadBytes', 'maximumSpans']
REFUSALS = ['empty', 'oversizedInput', 'truncated', 'unexpectedContainer', 'unexpectedType',
            'unsupportedLayout', 'unclassifiedPayloadTooLarge', 'tooManySpans', 'overlappingSpan',
            'spanOutOfRange']
# APIs that would turn inspection into a write, a network fetch or an upload.
WRITE_APIS = ['write(to:', 'createFile(', 'FileHandle(forWritingTo', '.removeItem(',
              'URLSession', 'replaceItemAt']
DOC_STATEMENTS = ['CBIN', 'npno', 'CNSP', 'offset 44', 'inspection-only', '.nsmp',
                  'USB or network transfer', 'AGPL', 'unknown', 'Out of scope']

source = (repo / 'Sources/NpnoPreflight.swift').read_text()
doc = (repo / 'Docs/NPNO-SUPPORT.md').read_text()
tests = (repo / 'Tests/NpnoPreflightTests.swift').read_text()
shell = (repo / 'Tests/test-library.sh').read_text()
workflow = (repo / '.github/workflows/distribution.yml').read_text()

for name in LIMITS:
    if f'var {name}' not in source:
        fail(f'Sources/NpnoPreflight.swift no longer declares the limit {name}')

for refusal in REFUSALS:
    if f'throw Refusal.{refusal}' not in source:
        fail(f'Sources/NpnoPreflight.swift no longer refuses {refusal}')
    if f'.{refusal}' not in tests:
        fail(f'Tests/NpnoPreflightTests.swift no longer exercises the {refusal} refusal')

# Inspection must refuse before it hashes: an oversized or malformed input is
# never read into the digest.
start = source.find('static func inspect(_ data: Data')
end = source.find('static func inspect(url:')
if start < 0 or end < 0 or end <= start:
    fail('cannot locate the in-memory inspection entry point')
else:
    body = source[start:end]
    if body.find('try classify(') < 0 or body.find('AssetDigest.sha256') < 0:
        fail('in-memory inspection no longer classifies and then hashes the input')
    elif body.find('try classify(') > body.find('AssetDigest.sha256'):
        fail('in-memory inspection hashes the input before it refuses a bad one')

for api in WRITE_APIS:
    if api in source:
        fail(f'Sources/NpnoPreflight.swift uses {api}, but this increment is read-only')

states = re.search(r'enum PlaybackState[^{]*\{(.*?)\n    \}', source, re.S)
if not states:
    fail('Sources/NpnoPreflight.swift has no PlaybackState')
elif len(re.findall(r'\bcase\s+[A-Za-z]', states.group(1))) != 1 \
        or 'inspectionOnly' not in states.group(1):
    fail('PlaybackState must publish exactly one state: inspectionOnly')
if re.search(r'case\s+playable', source):
    fail('Sources/NpnoPreflight.swift publishes a playable state it cannot support')

for statement in DOC_STATEMENTS:
    if statement not in doc:
        fail(f'Docs/NPNO-SUPPORT.md no longer states {statement!r}')

if '"$repo/Sources/NpnoPreflight.swift"' not in shell:
    fail('Tests/test-library.sh does not compile Sources/NpnoPreflight.swift')
if 'NpnoPreflightTests' not in shell:
    fail('Tests/test-library.sh does not run NpnoPreflightTests')
if 'Tests/test-npno-preflight.py' not in workflow:
    fail('.github/workflows/distribution.yml does not run this gate')

committed = [path.name for suffix in ('*.npno', '*.nsmp')
             for path in repo.rglob(suffix) if '.git' not in path.parts]
if committed:
    fail('private or binary Nord content is committed: ' + ', '.join(sorted(committed)))

if errors:
    for error in errors:
        print('FAIL:', error)
    raise SystemExit(1)
print(f'PASS: .npno preflight keeps {len(LIMITS)} limits and {len(REFUSALS)} refusals, '
      'refuses before hashing, stays read-only and inspection-only, and is wired into the gates')
