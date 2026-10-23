#!/usr/bin/env python3
"""Fail if a source checkout or built app includes sampled sound-library assets."""
import argparse,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--repo',type=pathlib.Path);p.add_argument('--bundle',type=pathlib.Path);args=p.parse_args()
forbidden={'.caf','.wav','.aif','.aiff','.flac','.mp3','.m4a','.sf2','.dls','.exs','.aupreset','.cst','.alp','.adg'}
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
bad=[str(x) for x in paths if x.suffix.lower() in forbidden or x.name in {'sound-library.json','manifest.json'} or 'Imported Sounds' in x.parts]
if bad:raise SystemExit('Sound-library assets must ship separately:\n'+'\n'.join(bad))
print('PASS: no sampled library assets in application source/bundle')
