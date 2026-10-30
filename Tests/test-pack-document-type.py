#!/usr/bin/env python3
import copy
import importlib.util
from pathlib import Path
import plistlib

repo = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('pack_gate', repo / 'Tools/check-pack-document-type.py')
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
for filename in ['Info-macOS.plist', 'Info-iOS.plist']:
    valid = plistlib.loads((repo / 'Resources' / filename).read_bytes())
    gate.validate(valid)
    for key in ['UTExportedTypeDeclarations', 'CFBundleDocumentTypes', 'LSSupportsOpeningDocumentsInPlace']:
        bad = copy.deepcopy(valid)
        bad.pop(key)
        try:
            gate.validate(bad)
        except ValueError:
            pass
        else:
            raise AssertionError('Missing document field accepted: ' + key)
print('PASS: both platforms register pack documents and missing receiver/type/in-place declarations fail')
