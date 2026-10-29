"""Portable artifact gate tests with disposable synthetic bundles and checkouts."""
from pathlib import Path
import subprocess
import tempfile

tool = Path(__file__).resolve().parents[1] / 'Tools/check-distribution.py'
notices = ('Airwindows-MIT.txt', 'EXS-Parser-MIT.md', 'StageKeys-Dense-Reverb-MIT.txt', 'OFL.txt')

# Naming no target would otherwise report PASS after checking nothing.
bare = subprocess.run(['python3', str(tool)], capture_output=True)
assert bare.returncode == 2 and b'--repo' in bare.stderr and not bare.stdout, bare.stdout + bare.stderr

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
    empty = resources / 'Empty.concert'
    empty.mkdir()
    check(app, False)
    empty.rmdir()
    for name in ('Personal.stagekeyspack', 'Personal.STAGEKEYSPACK'):
        pack=resources / name
        pack.write_bytes(b'synthetic personal pack')
        check(app, False)
        pack.unlink()
    pack=resources / 'Empty.stagekeyspack'
    pack.mkdir()
    check(app, False)
    pack.rmdir()
    seeded=resources / 'factory.txt'
    seeded.write_text('builtin-0')
    check(app, False)
    seeded.unlink()
    seeded=app / 'Contents' / 'MacOS' / 'StageKeys'
    seeded.parent.mkdir()
    seeded.write_bytes(b'synthetic executable: Soft Keys / Warm Pad / Glass Bells')
    check(app, False)
    seeded.write_bytes(b'x'*(1024*1024-3)+b'builtin-0')
    check(app, False)
    seeded.unlink()
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
repo_check({'Sources/Browser.swift': b'let id = "builtin-0"'}, False)
repo_check({'Sources/Models.swift': b'let names = ["Soft Keys", "Warm Pad", "Glass Bells"]'}, False)
repo_check({'Sources/Audio.swift': b'sk_note_on(pointer, 0, 60, 1, 0, 1)'}, False)
repo_check({'Tests/Fixture.swift': b'let names = ["Soft Keys", "Warm Pad", "Glass Bells"]'}, True)
repo_check({'Sources/Synth.c': b'void sk_note_on(void) {}'}, True)
repo_check({'Personal.stagekeyspack': b'fixture personal pack'}, False)
repo_check({'Personal.STAGEKEYSPACK': b'fixture personal pack'}, False)
repo_check({'Personal.stagekeyspack/README.txt': b'fixture nested pack'}, False)
repo_check({'Docs/stagekeyspack.md': b'fixture format documentation'}, True)
repo_check({'setlist.json': b'fixture user setlist'}, False)
repo_check({'setlist-v3-backup.json': b'fixture pre-migration setlist backup'}, False)
repo_check({'sound-library.json': b'fixture private library index'}, False)
repo_check({'The Base.patch/Contents/data.plist': b'fixture private MainStage patch'}, False)
repo_check({'Set.concert/displayState.plist': b'fixture private MainStage concert'}, False)
repo_check({'Song.als': b'fixture private Ableton set'}, False)
repo_check({'Samples/soft.sd2': b'fixture private sample'}, False)
repo_check({'note.aifc': b'fixture private sample'}, False)

def checkout_check(staged, untracked, expected, ignore=''):
    with tempfile.TemporaryDirectory() as temporary:
        checkout = Path(temporary)
        subprocess.run(['git', 'init', '-q', str(checkout)], check=True, capture_output=True)
        (checkout / '.gitignore').write_text(ignore)
        for name, content in untracked.items():
            target = checkout / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
        for name, content in staged.items():
            target = checkout / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            subprocess.run(['git', '-C', str(checkout), 'add', '-f', name], check=True, capture_output=True)
        result = subprocess.run(['python3', str(tool), '--repo', str(checkout)], capture_output=True)
        message = ','.join(list(staged) + list(untracked)) + result.stdout.decode() + result.stderr.decode()
        assert (result.returncode == 0) == expected, message

# An untracked private file is what a plain `git add -A` would commit next, so it is
# refused; an ignored one needs `git add -f` and deliberately stays out of scope.
checkout_check({'Sources/Model.swift': b'fixture source'}, {'note.aifc': b'fixture private sample'}, False)
checkout_check({'Sources/Model.swift': b'fixture source'}, {'Samples/soft.wav': b'fixture private sample'}, True, ignore='*.wav\n')
checkout_check({'Sources/Model.swift': b'fixture source'}, {'Sources/Extra.swift': b'fixture source'}, True)
checkout_check({'Sources/Model.swift': b'fixture source'}, {'Personal.stagekeyspack': b'fixture pack'}, False)
print('PASS: portable packs, no-target runs, missing notices, embedded samples, empty MainStage document directories, symlink bundles and private library, setlist, MainStage and Ableton content rejected')
