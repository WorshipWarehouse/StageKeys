#!/usr/bin/env python3
"""Fail if a source checkout or built app includes private library, user or vendor content.

Docs/DISTRIBUTION-PROVENANCE.md excludes the private sound library, imported
MainStage/Ableton material, user setlists and AU state from the distribution.
Sampled audio and instrument formats, MainStage documents and the data files the
app writes for the user are refused by file name, extension or path component, in
the source checkout and in a built bundle. These are name-based backstops against
accidental commits: private content the app renames, such as a per-identity
setlist-library file, is not detectable by name here.
"""
import argparse,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--repo',type=pathlib.Path);p.add_argument('--bundle',type=pathlib.Path);args=p.parse_args()
# Sampled audio (.aifc, .sd2 are AIFF-C and Sound Designer II), sampler instruments,
# channel strips and host devices/sets.
forbidden={'.caf','.wav','.aif','.aifc','.aiff','.sd2','.flac','.mp3','.m4a','.sf2','.dls','.exs','.aupreset','.cst','.alp','.adg','.als'}
# MainStage documents are bundles, so match the path component as well as a plain file name.
document_suffixes=('.patch','.concert')
# Files the app writes into its own data directory for the user.
user_files={'sound-library.json','manifest.json','setlist.json'}
def private(path):
 name=path.name.lower()
 return (path.suffix.lower() in forbidden or name in user_files
         or (name.startswith('setlist-v') and name.endswith('-backup.json'))
         or 'Imported Sounds' in path.parts
         or any(part.lower().endswith(document_suffixes) for part in path.parts))
paths=[]
if args.repo:paths += [pathlib.Path(x) for x in subprocess.check_output(['git','-C',str(args.repo),'ls-files','-z']).decode().split('\0') if x]
if args.bundle:
 if not args.bundle.is_dir() or args.bundle.is_symlink():
  raise SystemExit('Bundle must be an existing app directory, not a symlink')
 if not (args.bundle/'Contents'/'Info.plist').is_file() and not (args.bundle/'Info.plist').is_file():
  raise SystemExit('Bundle has no application Info.plist')
 bundle_paths = [x.relative_to(args.bundle) for x in args.bundle.rglob('*') if x.is_file()]
 paths += bundle_paths
 for notice in ('Airwindows-MIT.txt','EXS-Parser-MIT.md','StageKeys-Dense-Reverb-MIT.txt','OFL.txt'):
  if not any(x.name == notice for x in bundle_paths):
   raise SystemExit('Required bundled license missing: '+notice)
bad=[str(x) for x in paths if private(x)]
if bad:raise SystemExit('Private library, user and vendor assets must not be committed or shipped:\n'+'\n'.join(bad))
print('PASS: no private library, user or vendor assets in application source/bundle')
