#!/usr/bin/env python3
"""Fail when the saved-session schema boundary stops naming versions it cannot read."""
import re
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
errors = []


def fail(message):
    errors.append(message)


models = (repo / 'Sources/Models.swift').read_text()
store = (repo / 'Sources/Store.swift').read_text()
settings = (repo / 'Sources/SettingsViews.swift').read_text()
tests = (repo / 'Tests/SessionSchemaVersionTests.swift').read_text()
shell = (repo / 'Tests/test-library.sh').read_text()
workflow = (repo / '.github/workflows/distribution.yml').read_text()
doc_path = repo / 'Docs/SESSION-SCHEMA.md'
changelog = (repo / 'CHANGELOG.md').read_text()

for fragment in ['enum SetlistSchema', 'static let oldestSupported = 1', 'static let current = 4',
                 'static var supported: ClosedRange<Int> { oldestSupported...current }']:
    if fragment not in models:
        fail(f'Sources/Models.swift no longer declares {fragment!r}')
if 'var version = SetlistSchema.current' not in models:
    fail('Setlist no longer starts at the current schema version')
if 's.version = SetlistSchema.current' not in models:
    fail('Setlist.upgraded() no longer records the current schema version')

# The version guard must name the refused version instead of collapsing to `invalid`.
if 'guard SetlistSchema.supported.contains(version) else {' not in models:
    fail('Setlist.validate() no longer checks the schema boundary')
if 'throw SetlistError.unsupportedVersion(saved: version, supported: SetlistSchema.supported)' not in models:
    fail('an unsupported schema is no longer refused with its own version')
if re.search(r'\(\s*1\s*\.\.\.\s*4\s*\)\s*\.contains\(version\)', models):
    fail('Setlist still checks a hard-coded 1...4 literal instead of the schema boundary')
if re.search(r'min\(\s*version\s*,|max\(\s*version\s*,', models):
    fail('the schema version is clamped instead of refused')

error_block = re.search(r'enum SetlistError[^{]*\{(.*?)\n\}', models, re.S)
if not error_block:
    fail('Sources/Models.swift has no SetlistError')
else:
    block = error_block.group(1)
    if 'case unsupportedVersion(saved: Int, supported: ClosedRange<Int>)' not in block:
        fail('SetlistError no longer carries the unsupported schema version')
    if 'newer StageKeys version' not in block or 'left unchanged' not in block:
        fail('the unsupported-version message no longer explains the newer session or the untouched files')
    if 'does not read' not in block:
        fail('an unreadable old schema is no longer described as unreadable')

# The saved version must be read from an envelope before any payload assumption.
document = re.search(r'enum SessionDocument \{(.*?)\n\}', models, re.S)
if not document:
    fail('Sources/Models.swift no longer reads the saved schema through SessionDocument')
else:
    body = document.group(1)
    envelope_at = body.find('Envelope.self')
    payload_at = body.find('decode(Setlist.self')
    if envelope_at < 0:
        fail('SessionDocument no longer decodes a version envelope')
    if payload_at < 0 or envelope_at > payload_at:
        fail('SessionDocument decodes the payload before it checks the saved schema')
    if 'throw SetlistError.unsupportedVersion(saved: version, supported: SetlistSchema.supported)' not in body:
        fail('SessionDocument no longer refuses a newer schema before the payload')
if 'try SessionDocument.decode(data)' not in store:
    fail('the session load bypasses the version envelope')
if 'JSONDecoder().decode(Setlist.self' in store:
    fail('a setlist document is still decoded without checking its schema first')
library = (repo / 'Sources/SetlistLibrary.swift').read_text()
if 'JSONDecoder().decode(Setlist.self' in library:
    fail('a library setlist is still decoded without checking its schema first')
if 'SessionDocument.decode(' not in library:
    fail('the local library no longer reads setlists through the schema envelope')

if '@Published private(set) var sessionSavedByNewerVersion = false' not in store:
    fail('PerformanceStore no longer records that the saved session came from a newer version')
if 'saved > supported.upperBound' not in store or 'sessionSavedByNewerVersion = true' not in store:
    fail('the session load no longer classifies a newer schema separately from damage')

recovery = store.find('func recoverPreviousSession')
if recovery < 0:
    fail('PerformanceStore no longer offers session recovery')
else:
    body = store[recovery:]
    guard_at = body.find('guard !sessionSavedByNewerVersion else {')
    restore_at = body.find('RecoverableSessionFile.restore(saveURL)')
    if guard_at < 0 or restore_at < 0 or guard_at > restore_at:
        fail('session recovery no longer refuses to replace a newer-schema session')
    if 'sessionSavedByNewerVersion = false' not in body:
        fail('a completed recovery no longer clears the newer-version flag')

if 'store.sessionSavedByNewerVersion' not in settings:
    fail('Settings no longer distinguishes a newer-session refusal')
if 'Recovering an older copy would replace the newer session' not in settings:
    fail('Settings no longer explains why recovery is withheld for a newer session')
if settings.find('if store.sessionSavedByNewerVersion {') > settings.find('Button("Recover Previous Session")'):
    fail('the recovery button is no longer gated on the newer-version flag')

if not doc_path.exists():
    fail('Docs/SESSION-SCHEMA.md is missing')
else:
    doc = doc_path.read_text()
    for statement in ['SetlistSchema', 'schema 1', 'schema 4', 'newer', 'left unchanged',
                      'Recover Previous Session', 'autosave', 'envelope']:
        if statement not in doc:
            fail(f'Docs/SESSION-SCHEMA.md no longer states {statement!r}')

for fragment in ['SetlistSchema.supported', '.unsupportedVersion', 'sessionSavedByNewerVersion',
                 'recoverPreviousSession', 'SetlistSchema.current + 1', 'incompatibleNewer',
                 'changedShape', 'SessionDocument.decode']:
    if fragment not in tests:
        fail(f'Tests/SessionSchemaVersionTests.swift no longer exercises {fragment!r}')

if ' SessionSchemaVersionTests' not in shell:
    fail('Tests/test-library.sh does not run SessionSchemaVersionTests')
if 'Tests/test-session-schema.py' not in workflow:
    fail('.github/workflows/distribution.yml does not run this gate')
if '#20' not in changelog:
    fail('CHANGELOG.md no longer records the session schema entry')

if errors:
    for error in errors:
        print('FAIL:', error)
    raise SystemExit(1)
print('PASS: the session schema boundary reads 1–4, names newer sessions instead of calling them damaged, '
      'keeps their bytes through recovery and autosave, and is wired into the gates')
