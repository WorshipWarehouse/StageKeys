#!/usr/bin/env python3
"""Inventory every .patch and channel; distinguish archived presets from playable channels.
Usage: audit-mainstage-presets.py ARCHIVE_ROOT NATIVE_SOUND_LIBRARY_JSON
Writes JSON to stdout. Reads data only; never opens MainStage or modifies samples.
"""
import hashlib
import json
import plistlib
import sys
from pathlib import Path


def audit(root, entries):
    native = [e for e in entries if e.get('sound') or e.get('layer')]
    patches = []
    for path in sorted(root.rglob('*.patch')):
        if any(parent.suffix == '.patch' for parent in path.relative_to(root).parents):
            continue
        item = {'path': str(path.relative_to(root)), 'channels': []}
        try:
            if path.is_symlink():
                raise ValueError('Symbolic-link patch is not inspected')
            source = path / 'data.plist'
            if source.stat().st_size > 16_000_000:
                raise ValueError('Oversized patch document')
            data = plistlib.loads(source.read_bytes())
            if not isinstance(data, dict):
                raise ValueError('Unsupported patch document root')
            channels = data.get('channels')
            if not isinstance(channels, list) or not channels:
                raise ValueError('No supported channel list')
            for channel in channels:
                name = channel.get('Filename') if isinstance(channel, dict) else None
                row = {'file': name, 'nativeLibraryIDs': []}
                try:
                    if not isinstance(name, str) or not name:
                        raise ValueError('Missing channel filename')
                    file = path / name
                    if not file.resolve().is_relative_to(path.resolve()) or file.is_symlink():
                        raise ValueError('Unsafe channel reference')
                    if file.stat().st_size > 16_000_000:
                        raise ValueError('Oversized channel document')
                    digest = hashlib.sha256(file.read_bytes()).hexdigest()
                    row['sha256'] = digest
                    row['nativeLibraryIDs'] = [e['id'] for e in native if e['id'].startswith('mainstage-channel-' + digest + '-')]
                    row['status'] = 'native-channel' if row['nativeLibraryIDs'] else 'archived-only'
                except (OSError, ValueError) as error:
                    row.update(status='blocked', reason=str(error))
                item['channels'].append(row)
            item['status'] = 'native-channels' if all(c['status'] == 'native-channel' for c in item['channels']) else 'incomplete'
        except (OSError, ValueError, TypeError, plistlib.InvalidFileException) as error:
            item.update(status='blocked', reason=str(error))
        patches.append(item)
    channels = [c for p in patches for c in p['channels']]
    return {'summary': {'patches': len(patches), 'channels': len(channels), 'nativeChannelOccurrences': sum(c['status'] == 'native-channel' for c in channels), 'completeChannelCoveragePatches': sum(p['status'] == 'native-channels' for p in patches), 'blockedPatches': sum(p['status'] == 'blocked' for p in patches)}, 'limitations': ['Native-channel coverage means a retained playable channel, not verified full-patch audio, routing or effect parity.', 'Non-sampler instruments and missing source samples require further conversion; archived-only entries are not playable presets.'], 'patches': patches}


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    print(json.dumps(audit(Path(sys.argv[1]), json.loads(Path(sys.argv[2]).read_text())), indent=2))
