#!/usr/bin/env python3
"""Fail if a source checkout or built app includes private library, user or vendor content.

Docs/DISTRIBUTION-PROVENANCE.md excludes the private sound library, imported
MainStage/Ableton material, user setlists and AU state from the distribution.
Sampled audio and instrument formats, MainStage documents and the data files the
app writes for the user are refused by file name, extension or path component, in
the source checkout and in a built bundle. A source checkout is checked as a
plain `git add -A` would commit it: tracked files plus untracked files that the
checkout's .gitignore does not exclude. That exclusion is deliberate, because
private audio gitignored by the project needs `git add -f` to be committed at
all. One target must be named; with neither flag the gate would check nothing.
These are name-based backstops against accidental commits: private content the
app renames, such as a per-identity setlist-library file, is not detectable by
name here.
"""
import argparse,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--repo',type=pathlib.Path);p.add_argument('--bundle',type=pathlib.Path);args=p.parse_args()
if not args.repo and not args.bundle:
 p.error('name --repo and/or --bundle: this gate checks nothing without a target')
# Sampled audio (.aifc, .sd2 are AIFF-C and Sound Designer II), sampler instruments,
# channel strips and host devices/sets.
forbidden={'.caf','.wav','.aif','.aifc','.aiff','.sd2','.flac','.mp3','.m4a','.sf2','.dls','.exs','.aupreset','.cst','.alp','.adg','.als','.stagekeyspack'}
# MainStage documents are bundles, so match the path component as well as a plain file name.
document_suffixes=('.patch','.concert','.stagekeyspack')
# Files the app writes into its own data directory for the user.
user_files={'sound-library.json','manifest.json','setlist.json'}
def private(path):
 name=path.name.lower()
 return (path.suffix.lower() in forbidden or name in user_files
         or (name.startswith('setlist-v') and name.endswith('-backup.json'))
         or 'Imported Sounds' in path.parts
         or any(part.lower().endswith(document_suffixes) for part in path.parts))
def git(repo,*list_args):
 return [x for x in subprocess.check_output(['git','-C',str(repo),'ls-files','-z',*list_args]).decode().split('\0') if x]
def factory_marker(file,swift_source=False):
 if not file.is_file() or file.is_symlink():return False
 # Stream to bound memory for fat app binaries. Musical C generators remain
 # implementation/test code; only Swift product note entry points are refused.
 markers=[b'builtin-'];names=[b'soft keys',b'warm pad',b'glass bells'];found=set();tail=b''
 with file.open('rb') as stream:
  while chunk:=stream.read(1024*1024):
   data=(tail+chunk).lower()
   if any(marker in data for marker in markers):return True
   if swift_source and b'sk_note_on(' in data.replace(b' ',b''):return True
   found.update(name for name in names if name in data)
   if len(found)==len(names):return True
   tail=data[-128:]
 return False
paths=[]
if args.repo:
 # Untracked, not ignored paths are the ones `git add -A` would stage, so they are in scope.
 paths += [pathlib.Path(x) for x in git(args.repo)+git(args.repo,'--others','--exclude-standard')]
if args.bundle:
 if not args.bundle.is_dir() or args.bundle.is_symlink():
  raise SystemExit('Bundle must be an existing app directory, not a symlink')
 if not (args.bundle/'Contents'/'Info.plist').is_file() and not (args.bundle/'Info.plist').is_file():
  raise SystemExit('Bundle has no application Info.plist')
 entries = list(args.bundle.rglob('*'))
 paths += [x.relative_to(args.bundle) for x in entries]
 for notice in ('Airwindows-MIT.txt','EXS-Parser-MIT.md','StageKeys-Dense-Reverb-MIT.txt','OFL.txt'):
  if not any(x.is_file() and x.name == notice for x in entries):
   raise SystemExit('Required bundled license missing: '+notice)
factory=[]
if args.repo:
 for path in paths:
  if path.parts and path.parts[0]=='Sources' and path.suffix=='.swift' and factory_marker(args.repo/path,True):factory.append(str(path))
if args.bundle:
 for path in args.bundle.rglob('*'):
  if factory_marker(path):factory.append(str(path.relative_to(args.bundle)))
if factory:raise SystemExit('Factory sound content/product generator routes are not permitted: '+', '.join(factory))
bad=[str(x) for x in paths if private(x)]
if bad:raise SystemExit('Private library, user and vendor assets must not be committed or shipped:\n'+'\n'.join(bad))
print('PASS: no private library, user or vendor assets in application source/bundle')
