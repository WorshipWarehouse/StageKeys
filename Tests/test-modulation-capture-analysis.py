#!/usr/bin/env python3
import importlib.util,math,random,struct,sys,tempfile,wave
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

# An audio-level check: a wet capture delayed by 480 frames at 48 kHz is a
# 10 ms delay, and aligning each onset independently used to report zero.
def write(path:Path,samples:list[float],rate:int=48000)->None:
    with wave.open(str(path),"wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(b"".join(struct.pack("<h",max(-32768,min(32767,round(v*32767)))) for v in samples))

random.seed(7)
rate,delay=48000,480
dry=[0.2*random.uniform(-1,1) for _ in range(rate)]
wet=[0.0]*delay+dry[:-delay]
with tempfile.TemporaryDirectory() as directory:
    directory=Path(directory)
    a,b=directory/"dry.wav",directory/"wet.wav"
    write(a,dry);write(b,wet)
    comparison=module.comparator()
    points=module.trajectory(comparison.read_pcm(a),comparison.read_pcm(b),0,35)
    delays=[point[1] for point in points]
    assert all(abs(value-10)<1 for value in delays), f"delayed wet capture must report 10 ms, got {min(delays)}-{max(delays)} ms"
print("PASS: a 480-frame delayed wet capture reports a 10 ms delay instead of zero")

partial=[(i/100,12+3*math.sin(2*math.pi*.65*i/100+.7),.95) for i in range(80)]
result=module.fit(partial)
assert abs(result["frequencyHz"]-.65)<.002
assert abs(result["centerDelayMilliseconds"]-12)<.01
assert abs(result["delayDepthMilliseconds"]-3)<.01
try:
    module.fit([(0,1,.9)]*12)
    raise AssertionError("Singular timing fit accepted")
except ValueError: pass
