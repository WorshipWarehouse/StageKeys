#!/usr/bin/env python3
"""Validate measured source-backed loudness evidence; never adjusts audio or gain."""
import argparse
import itertools
import json
import math
from pathlib import Path


def evaluate(document, notes=(60, 74, 86), velocities=tuple(range(1, 128)), tolerance=1.0):
    if document.get('schemaVersion') != 1:
        raise ValueError('Unsupported calibration evidence version')
    sources = document['sources']
    reference, converted = sources['reference'], sources['stageKeys']
    if reference != converted:
        raise ValueError('Reference and StageKeys instrument/sample/zone identities differ')
    hashes = [reference['instrumentSHA256'], reference['zoneMapSHA256'], *reference['samples'].values()]
    if not reference['samples'] or any(not isinstance(h, str) or len(h) != 64 or any(c not in '0123456789abcdef' for c in h) for h in hashes):
        raise ValueError('Exact original instrument, sample and zone-map hashes are required')
    headroom = document['settings']['stageKeysOutputHeadroomDB']
    if isinstance(headroom, bool) or not isinstance(headroom, (int, float)) or not math.isfinite(headroom) or not -24 <= headroom <= 0:
        raise ValueError('Declare finite output headroom separately from source/channel/bus gain')
    settings = document['settings']
    for field in ('hostVelocityCurve', 'sourceGainDB', 'channelEQBypassed', 'busGainDB', 'effectsBypassed'):
        if field not in settings:
            raise ValueError('Missing isolated source setting: ' + field)
    isolation = {field: settings[field] for field in ('hostVelocityCurve', 'sourceGainDB', 'channelEQBypassed', 'busGainDB', 'effectsBypassed')}
    for field in ('channelEQBypassed', 'effectsBypassed'):
        if isolation[field] is not True:
            raise ValueError('Dry level evidence cannot declare active processing: ' + field + ' must be true')
    for field in ('hostVelocityCurve', 'sourceGainDB', 'busGainDB'):
        value = isolation[field]
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not -48 <= value <= 48:
            raise ValueError('Declare a finite isolated ' + field + ' in dB within -48 to 48, never a hidden or compensating value')
    if not notes or not velocities or any(type(n) is not int or not 0 <= n <= 127 for n in notes) or any(type(v) is not int or not 1 <= v <= 127 for v in velocities):
        raise ValueError('Invalid requested MIDI matrix')
    expected = set(itertools.product(notes, velocities, (False, True), ('isolated', 'chord')))
    measured, errors = set(), []
    for row in document['measurements']:
        if type(row['note']) is not int or type(row['velocity']) is not int or type(row['pedal']) is not bool:
            raise ValueError('MIDI identity and pedal state must be explicit')
        key = row['note'], row['velocity'], row['pedal'], row['gesture']
        if key not in expected or key in measured:
            raise ValueError('Unexpected or duplicate measurement: ' + str(key))
        if not row.get('sourceZoneID'):
            raise ValueError('Each measurement must identify the original selected zone/group')
        values = [row[k] for k in ('referenceRMS', 'stageKeysRMS', 'referencePeak', 'stageKeysPeak')]
        if any(isinstance(x, bool) or not isinstance(x, (float, int)) or not math.isfinite(x) or x <= 0 for x in values):
            raise ValueError('Silent, nonfinite or invalid measurement')
        ar, br, ap, bp = values
        if ap < ar or bp < br or max(ap, bp) >= 1:
            raise ValueError('Clipped or inconsistent RMS/peak evidence')
        measured.add(key)
        errors.append(dict(note=key[0], velocity=key[1], pedal=key[2], gesture=key[3],
                           errorDB=20 * math.log10(br / ar) - headroom))
    missing = sorted(expected - measured)
    maximum = max((abs(x['errorDB']) for x in errors), default=None)
    return dict(passed=not missing and maximum is not None and maximum <= tolerance,
                toleranceDB=tolerance, declaredHeadroomDB=headroom, declaredIsolation=isolation, measured=len(measured), expected=len(expected),
                missing=[list(x) for x in missing], maximumAbsoluteErrorDB=maximum, errors=errors,
                scope='Measured steady RMS only; attack/decay, layer transitions, timbre and physical latency require separate review')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--notes', default='60,74,86')
    parser.add_argument('--velocities', default=','.join(map(str, range(1, 128))))
    args = parser.parse_args()
    try:
        if args.evidence.stat().st_size > 16_000_000:
            raise ValueError('Evidence exceeds 16 MB')
        report = evaluate(json.loads(args.evidence.read_text()), tuple(map(int, args.notes.split(','))), tuple(map(int, args.velocities.split(','))))
        print(json.dumps(report, indent=2, allow_nan=False))
        raise SystemExit(0 if report['passed'] else 1)
    except (KeyError, TypeError, ValueError) as error:
        parser.exit(2, 'Invalid evidence: ' + str(error) + '\n')
