"""Portable checks for the optional personal tag extractor, with synthetic catalog exports."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

tool = Path(__file__).resolve().parents[1] / 'Tools/catalog-tags.py'
# Keys the app's SoundTags decoder requires; the optional ones may be absent.
required = {'category', 'type', 'timbres', 'articulations', 'sourceModel', 'inferred'}
optional = {'complexity', 'noteRanges', 'types', 'recommended'}

def extract(catalog):
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        source = root / 'catalog.json'
        source.write_text(json.dumps(catalog))
        output = root / 'source-sound-tags.json'
        result = subprocess.run([sys.executable, str(tool), str(source), str(output)], capture_output=True, text=True)
        text = output.read_text() if output.is_file() else ''
        return result, (json.loads(text) if text else None), text

def rows_of(catalog):
    result, rows, _ = extract(catalog)
    assert result.returncode == 0, result.stdout + result.stderr
    return rows, result.stdout

def facets(*declared):
    return [{'name': name, 'tags': [{'id': identifier, 'name': value}]} for name, identifier, value in declared]

def sound(identifier, name, tags, template=None):
    # Real exports carry playback payload beside the tags; none of it may be copied.
    return {'id': identifier, 'name': name, 'templateId': template or identifier,
            'tags': [{'id': tag} for tag in tags], 'samples': ['/private/secret.wav']}

catalog = {
    'Sample': [{'path': '/private/secret.wav'}],
    'Account': {'email': 'private@example.com'},
    'TagType': facets(
        ('Category', 'c1', 'Acoustic Piano & Keys'), ('Type', 't1', 'Felt Piano'),
        ('Timbre', 'm1', 'Warm'), ('Articulation', 'a1', 'Struck'),
        ('Source/Model', 's1', 'Sunday App sampler'), ('Sound Library', 'l1', 'Recommended'),
        ('Sound Library', 'l2', 'Prime'), ('Complexity', 'x1', 'Simple'),
        ('Complexity', 'x2', 'Medium'), ('Note Range', 'n1', 'Full Range'),
        ('Note Range', 'n2', 'Left Hand'), ('Note Range', 'n3', 'All')),
    'Sound': [
        # A saved copy appears first and must not redefine the factory row.
        sound('saved', 'Felt Room', ['c1', 'n2'], template='template'),
        sound('template', 'Felt Room', ['c1', 't1', 'm1', 'a1', 's1', 'l1', 'x1', 'n1']),
        sound('bare', 'Bare Pad', ['c1']),
        sound('prime', 'Prime Only', ['c1', 't1', 'l2']),
        sound('repeats', 'Repeated', ['c1', 't1', 'n1', 'n1']),
        sound('unknown-tag', 'Unknown Tag', ['c1', 'no-such-tag']),
        sound('refused', 'Refused Values', ['c1', 'n1', 'n3', 'x2']),
        sound('empty', '', []),
        sound('long', 'x' * 201, ['c1']),
    ],
}
rows, stdout = rows_of(catalog)
assert set(rows) == {'Felt Room', 'Bare Pad', 'Prime Only', 'Repeated', 'Unknown Tag', 'Refused Values'}, sorted(rows)
assert rows['Felt Room'] == {'category': 'Acoustic Piano & Keys', 'type': 'Felt Piano', 'timbres': ['Warm'],
                             'articulations': ['Struck'], 'sourceModel': 'Sunday App sampler', 'inferred': False,
                             'types': ['Felt Piano'], 'noteRanges': ['Full Range'], 'complexity': 'Simple',
                             'recommended': True}, rows['Felt Room']
# An undeclared facet stays unknown: no authored empty clear and no guessed source.
assert set(rows['Bare Pad']) == required, sorted(rows['Bare Pad'])
assert rows['Bare Pad']['category'] == 'Acoustic Piano & Keys' and rows['Bare Pad']['type'] == 'Other'
assert rows['Bare Pad']['sourceModel'] == 'Not Tagged'
assert set(rows['Prime Only']) == required | {'recommended', 'types'} and rows['Prime Only']['recommended'] is False
assert rows['Repeated']['noteRanges'] == ['Full Range'], 'Duplicate tag names must be listed once'
assert set(rows['Unknown Tag']) == required, 'Tags the export does not define must be ignored'
assert rows['Refused Values']['noteRanges'] == ['Full Range'] and 'complexity' not in rows['Refused Values']
assert len(required) == 6 and set(rows['Refused Values']) <= required | optional
assert 'skipped 2 unusable entries' in stdout, stdout
assert 'All' in stdout and 'Medium' in stdout, 'Unaccepted values must be reported, not silently dropped'
_, _, text = extract(catalog)
assert 'private' not in text and 'Sample' not in text and 'secret' not in text, 'Only sound tags may be copied'
assert text.startswith('{\n  "Bare Pad"'), 'Output must be deterministic and key-sorted'

for bad in ({'TagType': 'x', 'Sound': []}, {'Sound': []}, {'TagType': [], 'Sound': {}},
            {'TagType': [{'name': 'Category'}], 'Sound': []},
            {'TagType': [{'name': 'Category', 'tags': [{'id': 'c1'}]}], 'Sound': []},
            {'TagType': [], 'Sound': [{'id': 'a', 'name': 'A', 'templateId': 'a', 'tags': [{'name': 'x'}]}]},
            {'TagType': [], 'Sound': [{'id': 'a', 'name': 'A', 'tags': []}]}):
    result, rows, _ = extract(bad)
    assert result.returncode != 0 and rows is None, bad
    assert 'Traceback' not in result.stderr and 'Unsupported catalog export' in result.stderr, result.stderr
result, rows, _ = extract(catalog)
assert result.returncode == 0 and rows and 'No sound assets copied' in result.stdout
print('PASS: catalog tag extraction copies only declared tags, keeps undeclared facets unknown, ignores unknown tag ids, deduplicates repeated tags, prefers original templates, reports unaccepted values and refuses malformed exports')
