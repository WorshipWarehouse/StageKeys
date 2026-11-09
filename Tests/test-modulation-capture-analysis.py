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
