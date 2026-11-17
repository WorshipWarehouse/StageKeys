#!/usr/bin/env python3
import importlib.util,math,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("modulation",root/"Tools"/"analyze-modulation-capture.py")
module=importlib.util.module_from_spec(spec);sys.modules[spec.name]=module;spec.loader.exec_module(module)
points=[]
for index in range(180):
    time=index/30
    points.append((time,15+4*math.sin(2*math.pi*.65*time+.4),.9))
report=module.fit(points)
assert abs(report["frequencyHz"]-.65)<.002
assert abs(report["centerDelayMilliseconds"]-15)<.1
assert abs(report["delayDepthMilliseconds"]-4)<.1
print("PASS: phase-independent modulation fitting recovers LFO rate, center delay and depth")

# Non-integral and partial cycles require a joint offset/sine/cosine fit.
partial=[(i/100,12+3*math.sin(2*math.pi*.65*i/100+.7),.95) for i in range(80)]
result=module.fit(partial)
assert abs(result["frequencyHz"]-.65)<.002
assert abs(result["centerDelayMilliseconds"]-12)<.01
assert abs(result["delayDepthMilliseconds"]-3)<.01
try:
    module.fit([(0,1,.9)]*12)
    raise AssertionError("Singular timing fit accepted")
except ValueError: pass
# Shared frame origin preserves a physical 480-frame (10 ms) delay.
import random
rng=random.Random(724)
noise=[rng.uniform(-.4,.4) for _ in range(48000)]
audio=module.comparator()
points=module.trajectory(audio.Audio(48000,[noise]),audio.Audio(48000,[[0.0]*480+noise]),0,20)
assert all(abs(p[1]-10)<.001 for p in points)
