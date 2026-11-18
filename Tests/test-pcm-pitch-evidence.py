#!/usr/bin/env python3
import importlib.util
import math
import random
from pathlib import Path
spec=importlib.util.spec_from_file_location('pitch',Path(__file__).resolve().parents[1]/'Tools/measure-pcm-pitch.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
for rate in [35002,44100,48000]:
    for frequency in [130.813,261.626,523.251,1046.502]:
        samples=[.3*math.sin(2*math.pi*frequency*i/rate)+.07*math.sin(4*math.pi*frequency*i/rate) for i in range(round(rate*.5))]
        result=m.estimate(samples,rate)
        assert result is not None
        assert abs(1200*math.log2(result['frequencyHz']/frequency))<20,(rate,frequency,result)
assert m.estimate([0.0]*24000,48000) is None
rng=random.Random(721)
assert m.estimate([rng.uniform(-.3,.3) for _ in range(24000)],48000) is None
assert m.estimate([.3]*50,48000) is None
print('PASS: bounded pitch evidence distinguishes declared tones, octaves, silence, noise and short inputs')
