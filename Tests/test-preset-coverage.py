import importlib.util
import tempfile
import plistlib
import hashlib
from pathlib import Path
spec=importlib.util.spec_from_file_location('coverage',Path(__file__).resolve().parents[1]/'Tools/audit-mainstage-presets.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as tmp:
 root=Path(tmp);a=root/'One.patch';a.mkdir();(a/'Piano.cst').write_bytes(b'original channel');(a/'data.plist').write_bytes(plistlib.dumps({'channels':[{'Filename':'Piano.cst'},{'Filename':'Missing.cst'}]}));nested=a/'Ignored.patch';nested.mkdir();b=root/'Empty.patch';b.mkdir();(b/'data.plist').write_bytes(plistlib.dumps({}))
 digest=hashlib.sha256(b'original channel').hexdigest();entry={'id':'mainstage-channel-'+digest+'-instrument','sound':{}}
 x=module.audit(root,[entry]);assert x['summary']=={'patches':2,'channels':2,'nativeChannelOccurrences':0,'completeChannelCoveragePatches':0,'blockedPatches':1}
 entry['sound']={'kind':'samplerPreset'};x=module.audit(root,[entry]);assert x['summary']['nativeChannelOccurrences']==1
 rows=next(p for p in x['patches'] if p['path']=='One.patch')['channels'];assert rows[0]['nativeLibraryIDs']==[entry['id']] and rows[1]['status']=='blocked';assert x['summary']['completeChannelCoveragePatches']==0
print('PASS preset coverage: nested packages skipped, exact channel hashes, missing files and incomplete patches reported')
