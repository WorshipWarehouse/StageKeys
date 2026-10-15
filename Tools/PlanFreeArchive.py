#!/usr/bin/env python3
"""Plan/resume local free-archive conversions; never executes packages or host patches.
Usage: PlanFreeArchive.py catalog.json StageKeysDataDirectory captureFolder outputFolder
"""
import hashlib
import json
import re
import sys
from pathlib import Path


def plan(catalog, library, capture_root, sample_base=None):
    records = []
    for patch in catalog['patches']:
        collection = f"Sunday Free · Volume {patch['volume']}"
        hosts = [s for s in library if s.get('hostPath') and s['name'] == patch['name'] and s['collection'] == collection]
        if len(hosts) != 1:
            raise ValueError(f"Expected one installed archive entry: {collection}/{patch['name']}")
        host = hosts[0]
        native = next((s for s in library if s.get('sourceArchiveID') == host['id'] and (s.get('sound') or s.get('layer'))), None)
        slug = re.sub(r'[^\w .-]', '-', patch['name']).strip(' .')[:100]
        # Include stable archive identity so same-name patches cannot overwrite each other.
        preset = capture_root / f"V{patch['volume']:02d}--{slug}--{host['id'][-8:]}.exs"
        rhythmic = bool(re.search(r'arp|seq|rhyth|ryth|pulse', patch['name'], re.I))
        layered = len(patch.get('instruments', [])) > 1 or 'layered' in patch['name'].lower()
        records.append({
            'archiveID': host['id'], 'name': patch['name'], 'volume': patch['volume'],
            'sourcePatch': host['hostPath'], 'sourceInstruments': patch.get('instruments', []),
            'capturePreset': str(preset),
            'status': 'verified-native' if native else 'capture-ready' if preset.is_file() else 'needs-capture',
            'nativeLibraryID': native['id'] if native else None,
            'behaviorReview': rhythmic or layered,
            'captureNotes': 'Capture/translate rhythm, layers and modulation separately; tone capture is not a complete behavior conversion.' if rhythmic or layered else 'Sustained sounds need long captures and verified loops; inspect note-off response.',
            'job': {
                'preset': str(preset), 'sampleRoot': str((sample_base / preset.stem) if sample_base else capture_root),
                'name': patch['name'] + ' · Sampled',
                'collection': f"Sunday Free Native · Volume {patch['volume']}",
                'sourceArchiveID': host['id'],
                'notes': list(range(21, 109)), 'velocities': [32, 64, 100, 127],
                'seconds': 12, 'extendKeyRange': [21, 108],
                'requireSustain': bool(re.search(r'pad|soundbed', patch['name'], re.I)) and not rhythmic,
            },
        })
    if len({r['archiveID'] for r in records}) != len(records):
        raise ValueError('Duplicate archive identities')
    return records


def main():
    if len(sys.argv) != 5:
        raise SystemExit(__doc__)
    catalog_path, data, captures, out = map(Path, sys.argv[1:])
    catalog = json.loads(catalog_path.read_text())
    library = json.loads((data / 'sound-library.json').read_text())
    records = plan(catalog, library, captures.resolve(), Path.home() / "Music/Audio Music Apps/Samples/Auto Sampled")
    out.mkdir(parents=True, exist_ok=True)
    (out / 'conversion-queue.json').write_text(json.dumps(records, indent=2))
    for volume in sorted({r['volume'] for r in records}):
        jobs = [r['job'] for r in records if r['volume'] == volume and r['status'] == 'capture-ready']
        target = out / f'volume-{volume:02d}-ready.json'
        target.write_text(json.dumps({'jobs': jobs}, indent=2))
    counts = {state: sum(r['status'] == state for r in records) for state in ['verified-native', 'capture-ready', 'needs-capture']}
    (out / 'status.json').write_text(json.dumps({'total': len(records), **counts}, indent=2))
    print(json.dumps({'total': len(records), **counts}))


if __name__ == '__main__':
    main()
