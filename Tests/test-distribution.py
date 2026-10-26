"""Portable artifact gate tests with disposable synthetic bundles."""
from pathlib import Path
import subprocess
import tempfile

tool = Path(__file__).resolve().parents[1] / 'Tools/check-distribution.py'
notices = ('Airwindows-MIT.txt', 'EXS-Parser-MIT.md', 'StageKeys-Dense-Reverb-MIT.txt', 'OFL.txt')

def check(bundle, expected):
    result = subprocess.run(['python3', str(tool), '--bundle', str(bundle)], capture_output=True)
    assert (result.returncode == 0) == expected, result.stdout + result.stderr

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    check(root / 'Missing.app', False)
    app = root / 'StageKeys.app'
    resources = app / 'Contents' / 'Resources'
    resources.mkdir(parents=True)
    (app / 'Contents' / 'Info.plist').write_text('fixture')
    check(app, False)
    for notice in notices:
        (resources / notice).write_text('fixture notice')
    check(app, True)
    (resources / 'private.wav').write_bytes(b'fixture')
    check(app, False)
    (resources / 'private.wav').unlink()
    link = root / 'Linked.app'
    link.symlink_to(app, target_is_directory=True)
    check(link, False)
print('PASS: missing bundles, missing notices, embedded samples and symlink bundles rejected')
