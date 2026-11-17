"""Portable checks for the read-only MainStage archive audit, with synthetic archives."""
import hashlib
import json
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

tool = Path(__file__).resolve().parents[1] / 'Tools/audit-mainstage-presets.py'
limit = 16_000_000


def content(label):
    return ('channel:' + label).encode()


def write_patch(patch, names):
    patch.mkdir(parents=True, exist_ok=True)
    plist = {'channels': [{'Filename': name} for name in names]}
    (patch / 'data.plist').write_bytes(plistlib.dumps(plist))


def snapshot(root):
    rows = []
    for path in sorted(root.rglob('*')):
        relative = str(path.relative_to(root))
        if path.is_symlink():
            rows.append(('link', relative))
        elif path.is_dir():
            rows.append(('dir', relative))
        else:
            rows.append(('file', relative, path.stat().st_size))
    return rows


def audit(root, entries):
    with tempfile.TemporaryDirectory() as temporary:
        library = Path(temporary) / 'sound-library.json'
        library.write_text(json.dumps(entries))
        result = subprocess.run([sys.executable, str(tool), str(root), str(library)],
                                capture_output=True, text=True)
        return result, (json.loads(result.stdout) if result.stdout.strip() else None)


def build(root):
    native, archived = content('native'), content('archived')
    digest, other = (hashlib.sha256(value).hexdigest() for value in (native, archived))
    entries = [
        {'id': 'mainstage-channel-' + digest + '-0001', 'sound': {'path': 'Original Instruments/a.exs'}},
        {'id': 'mainstage-channel-' + digest + '-0002', 'layer': {'name': 'A'}},
        # An archive entry that is not playable must not count as a converted channel.
        {'id': 'mainstage-channel-' + other + '-0003', 'hostPath': '/Users/example/StageKeys-Library'},
    ]
    # Partial coverage: one retained native channel and one archived-only channel.
    write_patch(root / 'Zeta.patch', ['A.cst', 'B.cst'])
    (root / 'Zeta.patch' / 'A.cst').write_bytes(native)
    (root / 'Zeta.patch' / 'B.cst').write_bytes(archived)
    # Complete channel coverage for one patch.
    write_patch(root / 'Alpha.patch', ['C.cst'])
    (root / 'Alpha.patch' / 'C.cst').write_bytes(native)
    write_patch(root / 'Empty.patch', [])
    (root / 'ArrayRoot.patch').mkdir(parents=True)
    (root / 'ArrayRoot.patch' / 'data.plist').write_bytes(plistlib.dumps(['not a dictionary']))
    # A patch directory with no data.plist at all.
    (root / 'MissingDocument.patch').mkdir(parents=True)
    # An oversized patch document is refused before it is parsed.
    (root / 'Large.patch').mkdir(parents=True)
    (root / 'Large.patch' / 'data.plist').write_bytes(b'x' * (limit + 1))
    # A channel reference that escapes its patch is refused even though the target exists.
    write_patch(root / 'Escape.patch', ['../outside.cst'])
    (root / 'outside.cst').write_bytes(native)
    # A symbolic-link patch is never inspected, so its contents stay out of the report.
    (root / 'LinkTarget').mkdir(parents=True)
    (root / 'LinkTarget' / 'data.plist').write_bytes(plistlib.dumps({'channels': [{'Filename': 'Hidden.cst'}]}))
    (root / 'LinkTarget' / 'Hidden.cst').write_bytes(native)
    (root / 'Link.patch').symlink_to(root / 'LinkTarget', target_is_directory=True)
    # Only the outer patch is audited; the nested document is skipped instead of double-counted.
    write_patch(root / 'Nest.patch', ['D.cst'])
    (root / 'Nest.patch' / 'D.cst').write_bytes(content('nested-outer'))
    write_patch(root / 'Nest.patch' / 'Inner.patch', ['E.cst'])
    (root / 'Nest.patch' / 'Inner.patch' / 'E.cst').write_bytes(native)
    # A channel symlink is refused even when it resolves inside the patch.
    write_patch(root / 'ChannelSymlink.patch', ['Link.cst'])
    (root / 'ChannelSymlink.patch' / 'Target.cst').write_bytes(native)
    (root / 'ChannelSymlink.patch' / 'Link.cst').symlink_to('Target.cst')
    # An oversized channel document is refused after the patch itself is accepted.
    write_patch(root / 'ChannelLarge.patch', ['Huge.cst'])
    (root / 'ChannelLarge.patch' / 'Huge.cst').write_bytes(b'y' * (limit + 1))
    write_patch(root / 'ChannelAbsent.patch', ['Absent.cst'])
    # Unusable channel records block that row without discarding the patch.
    (root / 'ChannelUnnamed.patch').mkdir(parents=True)
    unnamed = {'channels': [{'Filename': ''}, 42]}
    (root / 'ChannelUnnamed.patch' / 'data.plist').write_bytes(plistlib.dumps(unnamed))
    return entries


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary) / 'Archive'
    entries = build(root)
    before = snapshot(root)
    result, report = audit(root, entries)
    assert result.returncode == 0, result.stdout + result.stderr
    assert report, 'The audit must write a report to stdout'
    assert snapshot(root) == before, 'The audit must not modify the archive it reads'

    patches = {row['path']: row for row in report['patches']}
    # The nested document is present on disk but must not appear as its own patch.
    assert set(patches) == {
        'Zeta.patch', 'Alpha.patch', 'Empty.patch', 'ArrayRoot.patch', 'MissingDocument.patch',
        'Large.patch', 'Escape.patch', 'Link.patch', 'Nest.patch', 'ChannelSymlink.patch',
        'ChannelLarge.patch', 'ChannelAbsent.patch', 'ChannelUnnamed.patch',
    }, sorted(patches)
    assert 'Nest.patch/Inner.patch' not in patches
    assert report['summary'] == {'patches': 13, 'channels': 10, 'nativeChannelOccurrences': 2,
                                 'completeChannelCoveragePatches': 1, 'blockedPatches': 5}, report['summary']

    native = hashlib.sha256(content('native')).hexdigest()
    zeta = patches['Zeta.patch']
    assert [row['file'] for row in zeta['channels']] == ['A.cst', 'B.cst']
    assert zeta['channels'][0] == {'file': 'A.cst', 'nativeLibraryIDs': [
        'mainstage-channel-' + native + '-0001', 'mainstage-channel-' + native + '-0002'],
        'sha256': native, 'status': 'native-channel'}, zeta['channels'][0]
    # Same content identity, but the only matching entry is not a playable conversion.
    assert zeta['channels'][1]['status'] == 'archived-only' and zeta['channels'][1]['nativeLibraryIDs'] == []
    assert zeta['status'] == 'incomplete'
    assert patches['Alpha.patch']['status'] == 'native-channels'
    assert patches['Nest.patch']['channels'][0]['status'] == 'archived-only'

    def reason(name):
        return patches[name].get('reason', '')

    assert reason('Empty.patch') == 'No supported channel list'
    assert reason('ArrayRoot.patch') == 'Unsupported patch document root'
    assert reason('Large.patch') == 'Oversized patch document'
    assert reason('Link.patch') == 'Symbolic-link patch is not inspected'
    assert patches['Link.patch']['channels'] == [], 'A refused patch must not be scored'
    assert 'No such file' in reason('MissingDocument.patch')
    assert [row['status'] for row in patches['Escape.patch']['channels']] == ['blocked']
    assert patches['Escape.patch']['channels'][0]['reason'] == 'Unsafe channel reference'
    assert patches['ChannelSymlink.patch']['channels'][0]['reason'] == 'Unsafe channel reference'
    assert patches['ChannelLarge.patch']['channels'][0]['reason'] == 'Oversized channel document'
    assert 'No such file' in patches['ChannelAbsent.patch']['channels'][0]['reason']
    assert [row['reason'] for row in patches['ChannelUnnamed.patch']['channels']] == [
        'Missing channel filename', 'Missing channel filename']
    # A blocked row is not a converted channel, so its patch cannot claim full coverage.
    for name in ('Escape.patch', 'ChannelSymlink.patch', 'ChannelLarge.patch', 'ChannelAbsent.patch',
                 'ChannelUnnamed.patch'):
        assert patches[name]['status'] == 'incomplete', name

    assert len(report['limitations']) == 2
    assert 'parity' in report['limitations'][0] and 'archived-only' in report['limitations'][1]
    # Reported patch paths are relative to the archive rather than absolute.
    assert not any(path.startswith('/') for path in patches), sorted(patches)

    # The same archive must produce byte-identical output on a second run.
    _, again = audit(root, entries)
    assert again == report, 'The audit must be deterministic'

    # The tool documents its arguments instead of auditing the wrong archive.
    for arguments in ([], [str(root)], [str(root), 'library.json', 'extra']):
        misuse = subprocess.run([sys.executable, str(tool), *arguments], capture_output=True, text=True)
        assert misuse.returncode != 0 and 'Usage' in misuse.stdout + misuse.stderr, arguments

print('PASS: archive audit matches channel identities to playable library entries, skips nested documents, '
      'refuses symlinked/oversized/unnamed/escaping documents and channels, counts coverage without scoring '
      'blocked or archive-only rows, leaves the archive unmodified and is deterministic')
