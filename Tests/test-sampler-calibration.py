import copy
import importlib.util
import itertools
from pathlib import Path

spec=importlib.util.spec_from_file_location('calibration',Path(__file__).resolve().parents[1]/'Tools/verify-sampler-calibration.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
source=dict(instrumentSHA256='a'*64,zoneMapSHA256='b'*64,samples={'original.wav':'c'*64})
document=dict(schemaVersion=1,sources=dict(reference=source,stageKeys=copy.deepcopy(source)),
              settings=dict(stageKeysOutputHeadroomDB=-1,hostVelocityCurve=-10,sourceGainDB=-6,channelEQBypassed=True,busGainDB=0,effectsBypassed=True),measurements=[])
for note,velocity,pedal,gesture in itertools.product((60,86),(38,127),(False,True),('isolated','chord')):
    document['measurements'].append(dict(note=note,velocity=velocity,pedal=pedal,gesture=gesture,sourceZoneID='original-zone',referenceRMS=.1,stageKeysRMS=.1*10**(-1/20),referencePeak=.2,stageKeysPeak=.2*10**(-1/20)))
def check(d):return module.evaluate(d,(60,86),(38,127))
assert check(document)['passed']
isolation={k:document['settings'][k] for k in ('hostVelocityCurve','sourceGainDB','channelEQBypassed','busGainDB','effectsBypassed')}
assert check(document)['declaredIsolation']==isolation
missing=copy.deepcopy(document);missing['measurements'].pop();assert not check(missing)['passed']
wrong=copy.deepcopy(document);wrong['measurements'][0]['stageKeysRMS']*=.5;assert not check(wrong)['passed']
for mutation in ('source','duplicate','silent','clipped','zone','eq','effects','eq_missing','curve_nan','gain_inf','bus_bool','bus_range'):
    bad=copy.deepcopy(document)
    if mutation=='source':bad['sources']['stageKeys']['instrumentSHA256']='d'*64
    if mutation=='duplicate':bad['measurements'].append(bad['measurements'][0])
    if mutation=='silent':bad['measurements'][0]['referenceRMS']=0
    if mutation=='clipped':bad['measurements'][0]['stageKeysPeak']=1
    if mutation=='zone':del bad['measurements'][0]['sourceZoneID']
    if mutation=='eq':bad['settings']['channelEQBypassed']=False
    if mutation=='effects':bad['settings']['effectsBypassed']=False
    if mutation=='eq_missing':del bad['settings']['channelEQBypassed']
    if mutation=='curve_nan':bad['settings']['hostVelocityCurve']=float('nan')
    if mutation=='gain_inf':bad['settings']['sourceGainDB']=float('inf')
    if mutation=='bus_bool':bad['settings']['busGainDB']=True
    if mutation=='bus_range':bad['settings']['busGainDB']=-60
    try:check(bad);raise AssertionError('Invalid evidence accepted: '+mutation)
    except ValueError:pass
print('PASS: source identities, velocity/pedal/chord coverage, explicit headroom, declared dry isolation and strict loudness evidence gates')
