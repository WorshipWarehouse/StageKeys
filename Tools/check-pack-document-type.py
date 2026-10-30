#!/usr/bin/env python3
"""Refuse app artifacts that cannot receive personal StageKeys packs from Files."""
import argparse
from pathlib import Path
import plistlib


def validate(info):
    identifier = 'studio.stagekeys.personal-pack'
    declarations = info.get('UTExportedTypeDeclarations', [])
    matches = [x for x in declarations if x.get('UTTypeIdentifier') == identifier]
    if len(matches) != 1:
        raise ValueError('Personal pack UTType is missing or ambiguous')
    item = matches[0]
    if 'public.data' not in item.get('UTTypeConformsTo', []):
        raise ValueError('Personal pack must conform to public.data')
    extensions = item.get('UTTypeTagSpecification', {}).get('public.filename-extension', [])
    if isinstance(extensions, str):
        extensions = [extensions]
    if 'stagekeyspack' not in extensions:
        raise ValueError('Personal pack extension is not registered')
    documents = info.get('CFBundleDocumentTypes', [])
    if not any(identifier in x.get('LSItemContentTypes', []) and x.get('CFBundleTypeRole') == 'Viewer' for x in documents):
        raise ValueError('App has no personal pack document receiver')
    if info.get('LSSupportsOpeningDocumentsInPlace') is not True:
        raise ValueError('Opening personal packs in place is disabled')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    args = parser.parse_args()
    info = args.bundle / 'Contents/Info.plist'
    if not info.exists():
        info = args.bundle / 'Info.plist'
    validate(plistlib.loads(info.read_bytes()))
    print('PASS: personal pack UTType, extension, document receiver and opening-in-place metadata')


if __name__ == '__main__':
    main()
