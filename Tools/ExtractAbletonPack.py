#!/usr/bin/env python3
"""Extract ADG/ADV and original audio from the observed pl-a Live Pack index.
No installers, Live devices, scripts, or package URLs are executed.
Usage: ExtractAbletonPack.py input.alp NEW-output-folder
"""
import gzip
import hashlib
import json
import mmap
from pathlib import Path
import re
import shutil
import struct
import sys
import tempfile

MAX_RAW = 8 * 1024**3
MAX_INDEX = 32 * 1024**2
EXTENSIONS = {'.adg', '.adv', '.aif', '.aiff', '.wav', '.caf', '.flac'}


def records(raw):
    if raw[:4] != b'pl-a' or len(raw) < 16:
        raise ValueError('Unsupported Live Pack header')
    index = struct.unpack_from('<Q', raw, 4)[0]
    if not 16 <= index < len(raw) or len(raw) - index > MAX_INDEX:
        raise ValueError('Invalid Live Pack index bounds')
    result = []
    for match in re.finditer(b'\x00\x0bPackageItem', raw[index:]):
        pos = index + match.end()
        if pos + 8 > len(raw):
            continue
        length = struct.unpack_from('<I', raw, pos + 4)[0]
        if not 1 <= length <= 256 or pos + 8 + length * 2 + 28 > len(raw):
            continue
        try:
            name = raw[pos + 8:pos + 8 + length * 2].decode('utf-16le')
        except UnicodeDecodeError:
            continue
        if Path(name).suffix.lower() not in EXTENSIONS:
            continue
        if '/' in name or '\\' in name or '\x00' in name or name in {'.', '..'}:
            raise ValueError('Unsafe archive filename')
        fields = pos + 8 + length * 2
        offset, size = struct.unpack_from('<QQ', raw, fields + 12)
        if not size or size > 512 * 1024**2 or offset < 16 or offset + size > index:
            raise ValueError('Invalid archive member bounds: ' + name)
        signature = raw[offset:offset + 4]
        if Path(name).suffix.lower() in {'.adg', '.adv'}:
            if not signature.startswith(b'\x1f\x8b'):
                raise ValueError('Invalid preset signature: ' + name)
        elif signature not in {b'FORM', b'RIFF', b'caff', b'fLaC'}:
            raise ValueError('Invalid audio signature: ' + name)
        result.append((name, offset, size))
        if len(result) > 20000:
            raise ValueError('Too many members')
    if not result:
        raise ValueError('No supported members in this Live Pack index')
    return result


def extract(source, target):
    if target.exists():
        raise FileExistsError('Choose a new output folder')
    # Decompress to a bounded spool instead of retaining a pack-sized allocation.
    with tempfile.TemporaryFile() as spool:
        total = 0
        with gzip.open(source, 'rb') as stream:
            while chunk := stream.read(1024 * 1024):
                total += len(chunk)
                if total > MAX_RAW:
                    raise ValueError('Pack expands beyond size limit')
                spool.write(chunk)
        spool.flush()
        with mmap.mmap(spool.fileno(), 0, access=mmap.ACCESS_READ) as raw:
            members = records(raw)
            target.mkdir(parents=True)
            manifest = []
            try:
                for name, offset, size in members:
                    folder = 'Presets' if Path(name).suffix.lower() in {'.adg', '.adv'} else 'Samples'
                    dest = target / folder / name
                    dest.parent.mkdir(exist_ok=True)
                    data = raw[offset:offset + size]
                    digest = hashlib.sha256(data).hexdigest()
                    if dest.exists():
                        if hashlib.sha256(dest.read_bytes()).hexdigest() != digest:
                            raise ValueError('Ambiguous duplicate sample/preset name: ' + name)
                    else:
                        dest.write_bytes(data)
                    manifest.append({'name': name, 'path': str(dest.relative_to(target)), 'sha256': digest, 'size': size})
                (target / 'extraction-report.json').write_text(json.dumps(manifest, indent=2))
            except BaseException:
                shutil.rmtree(target)
                raise
    return manifest


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    result = extract(Path(sys.argv[1]), Path(sys.argv[2]))
    print(json.dumps({'members': len(result), 'presets': sum(Path(r['name']).suffix.lower() in {'.adg', '.adv'} for r in result), 'originalAudioBytesPreserved': True}))
