#!/usr/bin/env python3
"""Fail when a built iOS application bundle would show a blank app icon.

The macOS target ships Resources/StageKeys.icns, but the iOS target ships
Resources/Assets.xcassets, and losing that catalog is silent: a cleared
ASSETCATALOG_COMPILER_APPICON_NAME still builds, links and launches, and only the
home screen shows the default blank tile. Losing the catalog once produced an app
that shipped with no icon at all, so the release gate checks every place a bundle
has to carry one: the Info.plist declarations, the compiled Assets.car rendition
those declarations name, and the loose fallback PNGs actool writes for older
systems. The fallback images are decoded too, so an icon file that exists but
holds one flat colour is refused instead of counted as present.

A bundle is read, never written: the catalog is inspected with assetutil, no PNG
is re-encoded and no image is resampled. Exit 0 means every declaration resolved
to real opaque artwork; 1 means the artifact would ship without its icon; 2 means
the arguments were unusable.
"""
import argparse
import json
import plistlib
import re
import struct
import subprocess
import zlib
from pathlib import Path

# The App Store marketing size, the only rendition a single-size app icon carries.
MARKETING_SIZE = 1024
# PNG colour type -> samples per pixel for the 8-bit, non-interlaced files actool writes.
CHANNELS = {0: 1, 2: 3, 4: 2, 6: 4}
POINTS = re.compile(r'^(.*?)(\d+)x(\d+)$')
SCALE = re.compile(r'@(\d)x(~ipad)?\.png$')


def fail(detail):
    raise SystemExit('Missing app icon: ' + detail)


def primary_icons(info):
    """Return {plist key: (icon name, fallback base files)} for each declared idiom."""
    declared = {}
    for key in ('CFBundleIcons', 'CFBundleIcons~ipad'):
        primary = (info.get(key) or {}).get('CFBundlePrimaryIcon') or {}
        name, files = primary.get('CFBundleIconName'), primary.get('CFBundleIconFiles') or []
        if isinstance(name, str) and name or isinstance(files, list) and files:
            declared[key] = (name, [str(entry) for entry in files] if isinstance(files, list) else [])
    return declared


def renditions(command, car):
    """Ask assetutil for the catalog's rendition table."""
    result = subprocess.run(command + ['--info', str(car)], capture_output=True, text=True)
    if result.returncode != 0:
        fail('the catalog reader could not read Assets.car: ' + (result.stderr.strip() or 'exit ' + str(result.returncode)))
    try:
        report = json.loads(result.stdout)
    except ValueError:
        fail('the catalog reader did not report readable Assets.car metadata')
    if not isinstance(report, list) or not all(isinstance(entry, dict) for entry in report):
        fail('the catalog reader did not report readable Assets.car metadata')
    return report


def read_png(path):
    """Decode an 8-bit PNG into (width, height, channels, rows) without external tools."""
    data = path.read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('not a PNG')
    position, header, compressed = 8, None, []
    while position + 8 <= len(data):
        length = struct.unpack('>I', data[position:position + 4])[0]
        kind, body = data[position + 4:position + 8], data[position + 8:position + 8 + length]
        position += 12 + length
        if kind == b'IHDR':
            try:
                header = struct.unpack('>IIBBBBB', body)
            except struct.error:
                raise ValueError('malformed IHDR chunk')
        elif kind == b'IDAT':
            compressed.append(body)
        elif kind == b'IEND':
            break
    if header is None:
        raise ValueError('no IHDR chunk')
    width, height, depth, colour, _, _, interlace = header
    channels = CHANNELS.get(colour)
    if depth != 8 or channels is None or interlace != 0:
        raise ValueError('only 8-bit non-interlaced greyscale, RGB, greyscale-alpha and RGBA are supported')
    try:
        raw = zlib.decompress(b''.join(compressed))
    except zlib.error:
        # Apple's CgBI variant stores the same rows as bare deflate.
        try:
            raw = zlib.decompress(b''.join(compressed), -15)
        except zlib.error:
            raise ValueError('corrupt image data')
    stride, rows, prior = width * channels, [], bytearray(width * channels)
    for y in range(height):
        start = y * (stride + 1)
        if start + 1 + stride > len(raw):
            raise ValueError('truncated image data')
        filter_type, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for x in range(stride):
            left = line[x - channels] if x >= channels else 0
            above = prior[x]
            corner = prior[x - channels] if x >= channels else 0
            if filter_type == 0:
                continue
            if filter_type == 1:
                line[x] = (line[x] + left) & 0xFF
            elif filter_type == 2:
                line[x] = (line[x] + above) & 0xFF
            elif filter_type == 3:
                line[x] = (line[x] + (left + above) // 2) & 0xFF
            elif filter_type == 4:
                estimate = left + above - corner
                distances = (abs(estimate - left), abs(estimate - above), abs(estimate - corner))
                line[x] = (line[x] + (left, above, corner)[distances.index(min(distances))]) & 0xFF
            else:
                raise ValueError('unknown row filter ' + str(filter_type))
        rows.append(bytes(line))
        prior = line
    return width, height, channels, rows


def inspect_fallback(path, base):
    """Refuse a fallback image whose pixels are missing, mis-sized or blank."""
    try:
        width, height, channels, rows = read_png(path)
    except (OSError, ValueError) as error:
        fail(path.name + ' is not a readable 8-bit PNG: ' + str(error))
    points = POINTS.match(base)
    if points:
        scale = int(SCALE.search(path.name).group(1))
        promised = (int(points.group(2)) * scale, int(points.group(3)) * scale)
        if (width, height) != promised:
            fail(path.name + ' is ' + str(width) + 'x' + str(height) + ' but its name promises ' + str(promised[0]) + 'x' + str(promised[1]))
    pixels = [row[x:x + channels] for row in rows for x in range(0, width * channels, channels)]
    if len(set(pixels)) < 2:
        fail(path.name + ' holds a single flat colour, so the shipped icon is blank artwork')
    if channels in (2, 4):
        visible = sum(1 for pixel in pixels if pixel[channels - 1] > 0)
        if visible != len(pixels):
            fail(path.name + ' has transparent pixels, but iOS requires an opaque app icon')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', required=True, type=Path, help='built .app to inspect')
    parser.add_argument('--assetutil', default=None, help='catalog reader override, for tests (default: xcrun assetutil)')
    args = parser.parse_args()
    bundle = args.bundle
    if not bundle.is_dir() or bundle.is_symlink():
        fail('the bundle ' + str(bundle) + ' is not an application directory')
    plist = bundle / 'Info.plist'
    if not plist.is_file():
        fail('the bundle has no Info.plist')
    try:
        info = plistlib.loads(plist.read_bytes())
    except (OSError, ValueError) as error:
        raise SystemExit('Invalid bundle: unreadable Info.plist: ' + str(error))
    declared = primary_icons(info)
    if 'CFBundleIcons' not in declared:
        fail('Info.plist declares no CFBundleIcons primary icon, so the home screen falls back to the blank default')
    for key, (name, files) in sorted(declared.items()):
        if not name:
            fail(key + ' declares no CFBundleIconName, so the compiled catalog is never consulted')
        if not files:
            fail(key + ' lists no CFBundleIconFiles, so older systems get no icon at all')
    car = bundle / 'Assets.car'
    if not car.is_file() or car.stat().st_size == 0:
        fail('the bundle has no compiled Assets.car, so the declared icon was never built in')
    report = renditions([args.assetutil] if args.assetutil else ['xcrun', 'assetutil'], car)
    icons = [entry for entry in report if entry.get('AssetType') == 'Icon Image']
    resolved = {}
    for name, _ in declared.values():
        matching = [entry for entry in icons if entry.get('Name') == name]
        if not matching:
            fail('Assets.car holds no Icon Image named ' + name + ', so the declared icon is absent from the compiled catalog')
        largest = max(matching, key=lambda entry: (entry.get('PixelWidth') or 0) * (entry.get('PixelHeight') or 0))
        if (largest.get('PixelWidth') or 0) < MARKETING_SIZE or (largest.get('PixelHeight') or 0) < MARKETING_SIZE:
            fail(name + ' is ' + str(largest.get('PixelWidth')) + 'x' + str(largest.get('PixelHeight')) + ' in Assets.car, smaller than the ' + str(MARKETING_SIZE) + ' marketing size')
        if largest.get('Opaque') is False:
            fail('the ' + name + ' rendition in Assets.car has an alpha channel, which App Store submission rejects')
        resolved[name] = (largest, sorted({str(entry.get('Idiom')) for entry in matching}))
    checked, seen = [], set()
    for key, (_, files) in sorted(declared.items()):
        for base in files:
            # actool writes the loose fallback beside the catalog, with a ~ipad suffix for the pad idiom.
            # Both idioms can declare the same fallback name, which is one file to inspect.
            candidates = [bundle / (base + '@' + scale + 'x' + idiom + '.png') for scale in ('2', '3') for idiom in ('', '~ipad')]
            present = [path for path in candidates if path.is_file()]
            if not present:
                fail(key + ' declares the ' + base + ' fallback but no ' + base + '@2x/@3x PNG was written')
            for path in present:
                if path in seen:
                    continue
                seen.add(path)
                inspect_fallback(path, base)
                checked.append(path.name)
    summary = ', '.join(name + ' ' + str(entry.get('PixelWidth')) + 'x' + str(entry.get('PixelHeight')) + ' for ' + '/'.join(idioms)
                        for name, (entry, idioms) in sorted(resolved.items()))
    print('PASS: app icon declared and compiled (' + summary + '), with opaque artwork in ' + ', '.join(sorted(checked)))


if __name__ == '__main__':
    main()
