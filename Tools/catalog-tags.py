#!/usr/bin/env python3
"""Extract optional personal tag metadata from an already exported local catalog.
No samples, presets, account tables or processing settings are copied.
Facets the export does not declare stay unknown: optional keys are omitted rather
than written as an authored empty clear, the required source key is labelled unknown
instead of asserting a model the export never named, and values the app refuses are
dropped and counted rather than discarding a whole sound's metadata.
"""
import argparse
import json
from pathlib import Path

UNKNOWN = 'Not Tagged'
REQUIRED_SOUND_KEYS = ('id', 'name', 'templateId', 'tags')
COMPLEXITY = ('Simple', 'Moderate', 'Complex')
NOTE_RANGES = ('Full Range', 'Left Hand', 'Mid Range', 'Right Hand')


def fail(detail):
    raise SystemExit('Unsupported catalog export: ' + detail)


def extract(catalog):
    if not isinstance(catalog, dict) or not isinstance(catalog.get('TagType'), list) or not isinstance(catalog.get('Sound'), list):
        fail('expected top-level TagType and Sound lists')
    facets = {}
    for facet in catalog['TagType']:
        if not isinstance(facet, dict) or not isinstance(facet.get('name'), str) or not isinstance(facet.get('tags'), list):
            fail('each TagType entry needs a name and a tag list')
        for tag in facet['tags']:
            if not isinstance(tag, dict) or not isinstance(tag.get('id'), str) or not isinstance(tag.get('name'), str):
                fail('each tag needs a string id and name')
            facets[tag['id']] = (facet['name'], tag['name'])
    rows, skipped, dropped = {}, 0, []
    # Prefer original templates; saved copies must not redefine factory tags.
    sounds = sorted(catalog['Sound'], key=lambda sound: not isinstance(sound, dict) or sound.get('id') != sound.get('templateId'))
    for sound in sounds:
        if not isinstance(sound, dict) or any(key not in sound for key in REQUIRED_SOUND_KEYS):
            fail('each Sound entry needs id, name, templateId and tags')
        name = sound['name']
        # The authored file is keyed by exact sound name, so an unusable name cannot be authored.
        if not isinstance(name, str) or not name or len(name) > 200 or not isinstance(sound['tags'], list):
            skipped += 1
            continue
        if name in rows:
            continue
        values = {}
        for tag in sound['tags']:
            if not isinstance(tag, dict) or not isinstance(tag.get('id'), str):
                fail('each sound tag needs a string id')
            known = facets.get(tag['id'])
            # The app refuses duplicate multi-value tags, so list each name once.
            if known and known[1] not in values.setdefault(known[0], []):
                values[known[0]].append(known[1])
        first = lambda key, default: next(iter(values.get(key, [])), default)
        row = dict(category=first('Category', 'Other'), type=first('Type', 'Other'),
                   timbres=values.get('Timbre', []), articulations=values.get('Articulation', []),
                   sourceModel=first('Source/Model', UNKNOWN), inferred=False)
        # Only a declared facet becomes an authored value, and only in the vocabulary the
        # app accepts. An absent or empty facet stays unknown instead of claiming a clear.
        for key, facet, allowed in (('types', 'Type', None), ('noteRanges', 'Note Range', NOTE_RANGES)):
            declared = values.get(facet, [])
            kept = [value for value in declared if allowed is None or value in allowed]
            dropped += [value for value in declared if allowed is not None and value not in allowed]
            if kept:
                row[key] = kept
        if values.get('Complexity'):
            level = first('Complexity', UNKNOWN)
            if level in COMPLEXITY:
                row['complexity'] = level
            else:
                dropped.append(level)
        if values.get('Sound Library'):
            row['recommended'] = 'Recommended' in values['Sound Library']
        rows[name] = row
    return rows, skipped, sorted(set(dropped))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('catalog', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    try:
        if args.catalog.stat().st_size > 16_000_000:
            parser.error('Catalog exceeds size limit')
        rows, skipped, dropped = extract(json.loads(args.catalog.read_text()))
    except (OSError, ValueError) as error:
        parser.exit(2, 'Invalid catalog: ' + str(error) + '\n')
    args.output.write_text(json.dumps(rows, indent=2, sort_keys=True) + '\n')
    print(f'Wrote tags for {len(rows)} sounds; skipped {skipped} unusable entries. No sound assets copied.')
    if dropped:
        print('Tag values not written because the app does not accept them: ' + ', '.join(dropped))


if __name__ == '__main__':
    main()
