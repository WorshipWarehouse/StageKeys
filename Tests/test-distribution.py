"""Portable artifact gate tests with disposable synthetic bundles and checkouts."""
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
    document = resources / 'The Base.patch'
    document.mkdir()
    (document / 'Contents.plist').write_text('fixture private MainStage document')
    check(app, False)
    child = next(iter(document.iterdir()))
    child.unlink()
    document.rmdir()
    link = root / 'Linked.app'
    link.symlink_to(app, target_is_directory=True)
    check(link, False)

def repo_check(files, expected):
    with tempfile.TemporaryDirectory() as temporary:
        checkout = Path(temporary)
        subprocess.run(['git', 'init', '-q', str(checkout)], check=True, capture_output=True)
        for name, content in files.items():
            target = checkout / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
        subprocess.run(['git', '-C', str(checkout), 'add', '-A', '-f'], check=True, capture_output=True)
        result = subprocess.run(['python3', str(tool), '--repo', str(checkout)], capture_output=True)
        message = ','.join(files) + result.stdout.decode() + result.stderr.decode()
        assert (result.returncode == 0) == expected, message

repo_check({'Sources/Model.swift': b'fixture source'}, True)
repo_check({'setlist.json': b'fixture user setlist'}, False)
repo_check({'setlist-v3-backup.json': b'fixture pre-migration setlist backup'}, False)
repo_check({'sound-library.json': b'fixture private library index'}, False)
repo_check({'The Base.patch/Contents/data.plist': b'fixture private MainStage patch'}, False)
repo_check({'Set.concert/displayState.plist': b'fixture private MainStage concert'}, False)
repo_check({'Song.als': b'fixture private Ableton set'}, False)
repo_check({'Samples/soft.sd2': b'fixture private sample'}, False)
repo_check({'note.aifc': b'fixture private sample'}, False)
print('PASS: missing bundles, missing notices, embedded samples, symlink bundles and private library, setlist, MainStage and Ableton content rejected')
