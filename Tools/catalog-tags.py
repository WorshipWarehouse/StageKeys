#!/usr/bin/env python3
"""Extract optional personal tag metadata from an already exported local catalog.
No samples, presets, account tables or processing settings are copied.
"""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('catalog', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
if args.catalog.stat().st_size > 16_000_000:
    parser.error('Catalog exceeds size limit')
catalog = json.loads(args.catalog.read_text())
facets = {tag['id']: (facet['name'], tag['name'])
          for facet in catalog['TagType'] for tag in facet['tags']}
result = {}
# Prefer original templates; saved copies must not redefine factory tags.
sounds = sorted(catalog['Sound'], key=lambda sound: sound['id'] != sound['templateId'])
for sound in sounds:
    if sound['name'] in result:
        continue
    values = {}
    for tag in sound['tags']:
        if tag['id'] in facets:
            facet, name = facets[tag['id']]
            values.setdefault(facet, []).append(name)
    first = lambda key, default: next(iter(values.get(key, [])), default)
    result[sound['name']] = dict(
        category=first('Category', 'Other'), type=first('Type', 'Other'),
        types=values.get('Type', []), timbres=values.get('Timbre', []),
        articulations=values.get('Articulation', []),
        sourceModel=first('Source/Model', 'Sampler'), inferred=False,
        noteRanges=values.get('Note Range', []),
        recommended='Recommended' in values.get('Sound Library', []))
    if values.get('Complexity'):
        result[sound['name']]['complexity'] = first('Complexity', 'Simple')
args.output.write_text(json.dumps(result, indent=2, sort_keys=True)+'\n')
print(f'Wrote tags for {len(result)} sounds. No sound assets copied.')
