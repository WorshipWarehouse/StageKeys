#!/usr/bin/env python3
import importlib.util
import math
from pathlib import Path
spec=importlib.util.spec_from_file_location('band_decays',Path(__file__).resolve().parents[1]/'Tools/compare-band-decays.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
rate=16000
for center,t60 in [(125,.8),(1000,1.4),(4000,.5)]:
    samples=[.3*math.sin(2*math.pi*center*i/rate)*10**(-3*i/rate/t60) for i in range(rate*3)]
    a=m.estimate([samples],rate,center)
    assert a['status']=='estimated',a
    assert abs(a['t20EstimatedT60Seconds']/t60-1)<.05,a
    b=m.estimate([samples,[-v for v in samples]],rate,center)
    assert b['status']=='estimated' and abs(b['t20EstimatedT60Seconds']-a['t20EstimatedT60Seconds'])<1e-9
    response=m.capture.Audio(rate,[samples])
    report=m.compare(response,m.capture.Audio(rate,[[v*.5 for v in samples]]),0)
    band=next(x for x in report['bands'] if x['centerHz']==center)
    assert abs(band['energyGainDeltaDB']+6.0206)<.001
    assert abs(band['estimatedT60DeltaSeconds'])<1e-9
    assert m.estimate([samples[:rate//5]],rate,center)['status']!='estimated'
assert m.estimate([[0.0]*rate],rate,1000)['status']=='silent'
for other,start in [(m.capture.Audio(48000,[[0.0]*10]),0),(m.capture.Audio(rate,[[float('nan')]*10]),0),(m.capture.Audio(rate,[[0.0]*10]),1),(m.capture.Audio(rate,[[0.0]*10]),float('nan'))]:
    try:m.compare(m.capture.Audio(rate,[[0.0]*10]),other,start)
    except ValueError:pass
    else:raise AssertionError('Invalid comparison admitted')
print('PASS octave decay: known exponential slopes/gain, anti-phase stereo, silent/truncated/nonfinite/mismatched refusal')
for sample_rate in (44100,48000,96000):
    t60=.9
    samples=[.2*math.sin(2*math.pi*1000*i/sample_rate)*10**(-3*i/sample_rate/t60) for i in range(sample_rate*2)]
    fit=m.estimate([samples],sample_rate,1000)
    assert fit['status']=='estimated' and abs(fit['t20EstimatedT60Seconds']/t60-1)<.05,fit
print('PASS octave decay sample rates: 44.1/48/96 kHz')
