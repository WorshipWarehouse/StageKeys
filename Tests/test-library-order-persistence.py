#!/usr/bin/env python3
"""Fail when the library forgets the order the performer last chose (#17).

The library reopened with a fresh `LibraryQuery()` every time, so the chosen
order fell back to Name and a Random order reshuffled on the next launch. This
gate checks that the order and its seed are stored and restored, that a restored
random order reuses the stored seed instead of drawing a new one, and that the
regression program and job wiring exist.
"""
import re
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
errors = []


def fail(message):
    errors.append(message)


model = (repo / 'Sources/LibraryBrowserModel.swift').read_text()
browser = (repo / 'Sources/SoundBrowser.swift').read_text()
test_path = repo / 'Tests/LibraryOrderPersistenceTests.swift'
shell = (repo / 'Tests/test-library.sh').read_text()
workflow = (repo / '.github/workflows/distribution.yml').read_text()
doc_path = repo / 'Docs/LIBRARY-VIEW-ORDER.md'
changelog = (repo / 'CHANGELOG.md').read_text()

# The default stays Name, so a library opened without stored preferences is
# unchanged. Persistence is an additive restore path, not a new default.
if 'var ordering:LibrarySort = .name' not in model:
    fail('Sources/LibraryBrowserModel.swift no longer defaults the library order to Name')

restore = re.search(r'init\(storedOrder: String\?, storedSeed: UInt64\?\) \{(.*?)\n    \}', model, re.S)
if not restore:
    fail('LibraryQuery no longer restores a stored order and seed')
else:
    body = restore.group(1)
    if 'flatMap(LibrarySort.init(rawValue:))' not in body:
        fail('an unknown persisted order no longer falls back to Name')
    if 'ascending = order == .name || order == .recommended' not in body:
        fail('a restored order no longer restores its direction')
    if 'sort = nil' not in body:
        fail('a restored order no longer clears a manual facet sort')
    random_seed = re.search(r'if order == \.random \{(.*?)\n        \}', body, re.S)
    if not random_seed:
        fail('a restored Random order no longer handles its seed')
    elif 'seed == 0 ? UInt64.random(in: 1...UInt64.max) : seed' not in random_seed.group(1):
        fail('a restored Random order draws a new seed or keeps the 0 sentinel')
if 'shuffleSeed=UInt64.random(in:1...UInt64.max)' not in model.replace(' ', ''):
    fail('choosing Random no longer generates a non-zero shuffle seed')

# The view must store both halves of the preference and hand them back on open.
for fragment in ['@AppStorage("library.order")', '@AppStorage("library.shuffleSeed")',
                 'query=LibraryQuery(storedOrder:savedOrder,storedSeed:UInt64(savedSeed))']:
    if fragment not in browser.replace(' ', ''):
        fail(f'Sources/SoundBrowser.swift no longer persists the library order: {fragment!r} missing')
if '.onChange(of:query.ordering)' not in browser.replace(' ', ''):
    fail('a changed library order is not stored')
if '.onChange(of:query.shuffleSeed)' not in browser.replace(' ', ''):
    fail('the Random seed is not stored with the order')
if re.search(r'@AppStorage\("library\.shuffleSeed"\)[^\n]*UInt64', browser):
    fail('@AppStorage cannot store a UInt64 seed; persist it as text')

# Leaving the browser through the empty-state actions used to rebuild the query,
# which made the ordering observers store Name over the performer's preference.
if re.search(r'Button\("Add Audio Unit"\)\{collection="Audio Units";query=LibraryQuery\(\)\}', browser):
    fail('the Add Audio Unit action replaces the whole library query and overwrites the saved order')
if re.search(r'Button\("MIDI Routing"\)\{collection="External MIDI";query=LibraryQuery\(\)\}', browser):
    fail('the MIDI Routing action replaces the whole library query and overwrites the saved order')
clear = re.search(r'private func clearTransientQuery\(\) \{(.*?)\n    \}', browser, re.S)
if not clear:
    fail('Sources/SoundBrowser.swift no longer clears transient library state separately')
else:
    body = clear.group(1)
    if 'query.ordering' in body or 'query.shuffleSeed' in body:
        fail('the transient clear rewrites the saved library order')
    if 'LibraryQuery()' in body:
        fail('the transient clear still replaces the whole library query')
if 'clearTransientQuery()' not in browser:
    fail('the empty-state actions no longer use the transient clear')

if not test_path.exists():
    fail('Tests/LibraryOrderPersistenceTests.swift is missing')
else:
    test = test_path.read_text()
    for fragment in ['storedOrder:"Random"', 'storedSeed:', 'storedOrder:"Rating"',
                     'storedOrder:"Bogus"', 'shuffleSeed != 0', 'shuffleSeed == 0',
                     'library order', 'keeps the saved Random order']:
        if fragment not in test:
            fail(f'Tests/LibraryOrderPersistenceTests.swift no longer exercises {fragment!r}')

if not doc_path.exists():
    fail('Docs/LIBRARY-VIEW-ORDER.md is missing')
else:
    doc = doc_path.read_text()
    for statement in ['library.order', 'library.shuffleSeed', 'Random', 'relaunch',
                      'Name', 'not persisted']:
        if statement not in doc:
            fail(f'Docs/LIBRARY-VIEW-ORDER.md no longer states {statement!r}')
if '#17' not in changelog:
    fail('CHANGELOG.md does not record the #17 library order fix')

if ' LibraryOrderPersistenceTests' not in shell:
    fail('Tests/test-library.sh does not run LibraryOrderPersistenceTests')
if 'Tests/test-library-order-persistence.py' not in workflow:
    fail('.github/workflows/distribution.yml does not run this gate')

if errors:
    for error in errors:
        print(f'FAIL: {error}')
    raise SystemExit(1)
print('PASS: the library restores its stored order and reproduces a stored Random order across launches')
