#!/usr/bin/env python3
"""Run the existing Swift corpus using one testable core module; no third-party dependencies."""
import argparse, pathlib, re, subprocess, os, time, json, uuid
p=argparse.ArgumentParser();p.add_argument('source');p.add_argument('build');p.add_argument('tests',nargs='*');a=p.parse_args()
r=pathlib.Path(a.source).resolve();b=pathlib.Path(a.build).resolve();
if b == r or r in b.parents: p.error('Choose a build directory outside the source checkout')
b.mkdir(parents=True,exist_ok=True)
s=(r/'Tests/test-library.sh').read_text();sources=[r/x for x in re.findall(r'"\$repo/(Sources/[^"\n]+\.swift)"',s)]
tests=a.tests or re.search(r'else tests=\((.*?)\); fi',s).group(1).split()
def run(cmd,env=None):
 print('+', ' '.join(str(x) for x in cmd[:5]),flush=True);subprocess.run(list(map(str,cmd)),check=True,env=env,timeout=300)
for name in ['Synth','CreamCoat']:run(['xcrun','clang','-std=c11','-O2','-c',r/f'Sources/{name}.c','-o',b/f'{name}.o'])
common=['xcrun','swiftc','-DDEBUG','-module-cache-path',b/'modules','-import-objc-header',r/'Sources/Bridge.h']
run(common+['-enable-testing','-emit-library','-emit-module','-parse-as-library','-module-name','StageKeysVerificationCore']+sources+[b/'Synth.o',b/'CreamCoat.o','-framework','CoreMIDI','-lz','-o',b/'libStageKeysVerificationCore.dylib','-emit-module-path',b/'StageKeysVerificationCore.swiftmodule'])
results=[]
for test in tests:
 path=b/f'{test}.swift';path.write_text('@testable import StageKeysVerificationCore\n'+(r/f'Tests/{test}.swift').read_text())
 try:
  run(common+['-parse-as-library','-I',b,'-L',b,'-lStageKeysVerificationCore','-Xlinker','-rpath','-Xlinker',b,path,'-framework','CoreMIDI','-lz','-o',b/test])
  env=os.environ.copy();env['STAGEKEYS_DATA_DIR']=str(b/f'data-{test}-{uuid.uuid4().hex}');run([b/test],env);results.append({'test':test,'passed':True})
 except subprocess.CalledProcessError:results.append({'test':test,'passed':False});(b/'results.json').write_text(json.dumps(results,indent=2));raise
(b/'results.json').write_text(json.dumps(results,indent=2))
