"""Portable app icon gate tests with disposable synthetic bundles and catalogs."""
import json
import plistlib
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path

tool = Path(__file__).resolve().parents[1] / 'Tools/check-app-icon.py'

# The gate reads the catalog with assetutil, so the fixture stands in for it and
# reports what a compiled catalog of the same fixture declares.
STUB = '''#!/usr/bin/env python3
import pathlib
import sys
here = pathlib.Path(__file__).parent
if (here / 'broken').exists():
    sys.stderr.write('assetutil: unreadable catalog\\n')
    raise SystemExit(1)
sys.stdout.write((here / 'catalog-report.json').read_text())
'''


def chunk(kind, body):
    return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body) & 0xFFFFFFFF)


def png(width, height, rows, filters=(0,)):
    """Encode 8-bit RGBA rows, cycling one PNG row filter per row."""
    raw, prior = bytearray(), bytes(width * 4)
    for index, row in enumerate(rows):
        kind = filters[index % len(filters)]
        line = bytearray(len(row))
        for x, value in enumerate(row):
            left = row[x - 4] if x >= 4 else 0
            above = prior[x]
            corner = prior[x - 4] if x >= 4 else 0
            if kind == 0:
                predictor = 0
            elif kind == 1:
                predictor = left
            elif kind == 2:
                predictor = above
            elif kind == 3:
                predictor = (left + above) // 2
            else:
                estimate = left + above - corner
                distances = (abs(estimate - left), abs(estimate - above), abs(estimate - corner))
                predictor = (left, above, corner)[distances.index(min(distances))]
            line[x] = (value - predictor) & 0xFF
        raw.append(kind)
        raw += line
        prior = row

    header = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(bytes(raw))) + chunk(b'IEND', b'')


def artwork(width, height, shade=None, alpha=255):
    rows = []
    for y in range(height):
        row = bytearray()
        for x in range(width):
            level = shade if shade is not None else (x * 255) // max(width - 1, 1)
            row += bytes((level, level // 2, 255 - level, alpha))
        rows.append(bytes(row))
    return rows


def icon_report(names=('AppIcon',), size=1024, opaque=True):
    return [{'AssetType': 'Icon Image', 'Name': name, 'Idiom': idiom, 'PixelWidth': size,
             'PixelHeight': size, 'Opaque': opaque} for name in names for idiom in ('phone', 'pad')]


def make_bundle(folder):
    bundle = folder / 'StageKeysMobile.app'
    bundle.mkdir(parents=True)
    info = {'CFBundleIdentifier': 'fixture.app',
            'CFBundleIcons': {'CFBundlePrimaryIcon': {'CFBundleIconName': 'AppIcon',
                                                     'CFBundleIconFiles': ['AppIcon60x60']}},
            'CFBundleIcons~ipad': {'CFBundlePrimaryIcon': {'CFBundleIconName': 'AppIcon',
                                                          'CFBundleIconFiles': ['AppIcon60x60', 'AppIcon76x76']}}}
    (bundle / 'Info.plist').write_bytes(plistlib.dumps(info))
    (bundle / 'Assets.car').write_bytes(b'fixture compiled catalog')
    for name, size in (('AppIcon60x60@2x.png', 120), ('AppIcon76x76@2x~ipad.png', 152)):
        (bundle / name).write_bytes(png(size, size, artwork(size, size)))
    return bundle, info


def stub(folder, report=None, broken=False):
    reader = folder / 'assetutil'
    reader.write_text(STUB)
    reader.chmod(0o755)
    (folder / 'catalog-report.json').write_text(json.dumps(icon_report() if report is None else report))
    marker = folder / 'broken'
    if broken:
        marker.write_text('fixture failure')
    elif marker.exists():
        marker.unlink()
    return reader


def check(bundle, expected, reader, reason=None):
    result = subprocess.run(['python3', str(tool), '--bundle', str(bundle), '--assetutil', str(reader)],
                            capture_output=True, text=True)
    message = str(bundle) + result.stdout + result.stderr
    assert (result.returncode == 0) == expected, message
    if reason:
        assert reason in result.stderr, message
    return result


# Naming no bundle would otherwise report PASS after inspecting nothing.
bare = subprocess.run(['python3', str(tool)], capture_output=True, text=True)
assert bare.returncode == 2 and '--bundle' in bare.stderr and not bare.stdout, bare.stdout + bare.stderr

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)

    def fresh(label):
        folder = root / label
        folder.mkdir()
        bundle, info = make_bundle(folder)
        return folder, bundle, info

    folder, bundle, info = fresh('good')
    reader = stub(folder)
    passed = check(bundle, True, reader)
    assert 'AppIcon 1024x1024' in passed.stdout and 'pad/phone' in passed.stdout, passed.stdout
    # Both idioms declare AppIcon60x60, but it is one file and is reported once.
    assert passed.stdout.count('AppIcon60x60@2x.png') == 1, passed.stdout
    check(root / 'Missing.app', False, reader, 'not an application directory')

    folder, bundle, info = fresh('no-plist-icons')
    del info['CFBundleIcons'], info['CFBundleIcons~ipad']
    (bundle / 'Info.plist').write_bytes(plistlib.dumps(info))
    check(bundle, False, stub(folder), 'declares no CFBundleIcons primary icon')

    folder, bundle, info = fresh('no-name')
    info['CFBundleIcons']['CFBundlePrimaryIcon'] = {'CFBundleIconFiles': ['AppIcon60x60']}
    (bundle / 'Info.plist').write_bytes(plistlib.dumps(info))
    check(bundle, False, stub(folder), 'declares no CFBundleIconName')

    folder, bundle, info = fresh('no-car')
    (bundle / 'Assets.car').unlink()
    check(bundle, False, stub(folder), 'no compiled Assets.car')

    folder, bundle, info = fresh('empty-car')
    (bundle / 'Assets.car').write_bytes(b'')
    check(bundle, False, stub(folder), 'no compiled Assets.car')

    # The declarations and the loose PNGs are intact here; only the catalog lost the icon.
    folder, bundle, info = fresh('catalog-without-icon')
    check(bundle, False, stub(folder, icon_report(('SomethingElse',))), 'no Icon Image named AppIcon')

    folder, bundle, info = fresh('small-rendition')
    check(bundle, False, stub(folder, icon_report(size=512)), 'smaller than the 1024 marketing size')

    folder, bundle, info = fresh('alpha-rendition')
    check(bundle, False, stub(folder, icon_report(opaque=False)), 'has an alpha channel')

    folder, bundle, info = fresh('broken-reader')
    check(bundle, False, stub(folder, broken=True), 'unreadable catalog')

    folder, bundle, info = fresh('unreadable-report')
    reader = stub(folder)
    (folder / 'catalog-report.json').write_text('not JSON at all')
    check(bundle, False, reader, 'did not report readable Assets.car metadata')

    folder, bundle, info = fresh('no-fallback')
    (bundle / 'AppIcon76x76@2x~ipad.png').unlink()
    check(bundle, False, stub(folder), 'no AppIcon76x76@2x/@3x PNG was written')

    folder, bundle, info = fresh('wrong-size')
    (bundle / 'AppIcon60x60@2x.png').write_bytes(png(240, 240, artwork(240, 240)))
    check(bundle, False, stub(folder), 'but its name promises 120x120')

    folder, bundle, info = fresh('flat')
    (bundle / 'AppIcon60x60@2x.png').write_bytes(png(120, 120, artwork(120, 120, shade=40)))
    check(bundle, False, stub(folder), 'single flat colour')

    folder, bundle, info = fresh('transparent')
    (bundle / 'AppIcon60x60@2x.png').write_bytes(png(120, 120, artwork(120, 120, alpha=0)))
    check(bundle, False, stub(folder), 'requires an opaque app icon')

    folder, bundle, info = fresh('not-a-png')
    (bundle / 'AppIcon60x60@2x.png').write_bytes(b'not a PNG at all')
    check(bundle, False, stub(folder), 'not a readable 8-bit PNG')

    # A well-formed PNG wrapper around bytes that are not image data is refused, not traced back.
    folder, bundle, info = fresh('corrupt-pixels')
    signature = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 120, 120, 8, 6, 0, 0, 0))
    (bundle / 'AppIcon60x60@2x.png').write_bytes(signature + chunk(b'IDAT', b'not deflate data') + chunk(b'IEND', b''))
    check(bundle, False, stub(folder), 'not a readable 8-bit PNG')

    # Every PNG row filter must decode, not just the unfiltered one actool tends to write.
    folder, bundle, info = fresh('filters')
    for name, size in (('AppIcon60x60@2x.png', 120), ('AppIcon76x76@2x~ipad.png', 152)):
        (bundle / name).write_bytes(png(size, size, artwork(size, size), filters=(0, 1, 2, 3, 4)))
    check(bundle, True, stub(folder))

    folder, bundle, info = fresh('linked')
    link = folder / 'Linked.app'
    link.symlink_to(bundle, target_is_directory=True)
    check(link, False, stub(folder), 'not an application directory')

print('PASS: app icon gate accepts a declared, compiled, opaque icon and refuses a missing declaration, catalog rendition, marketing size, opacity, fallback PNG, named pixel size, flat or transparent artwork, unreadable catalog and symlinked bundle')
