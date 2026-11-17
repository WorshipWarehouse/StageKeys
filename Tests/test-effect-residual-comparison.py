#!/usr/bin/env python3
import importlib.util
import math
import struct
import sys
import tempfile
import wave
from pathlib import Path

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("residuals", root / "Tools" / "compare-effect-residuals.py")
residuals = importlib.util.module_from_spec(spec)
assert spec.loader
sys.modules[spec.name] = residuals
spec.loader.exec_module(residuals)
comparison = residuals.load_comparator()


def write(path: Path, samples: list[float]) -> None:
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(48000)
        output.writeframes(b"".join(struct.pack("<h", round(max(-1, min(1, value)) * 32767)) for value in samples))


with tempfile.TemporaryDirectory() as folder:
    folder = Path(folder)
    dry = [0.0] * 100 + [0.4 * math.sin(index * 0.07) for index in range(6000)]
    clean = dry.copy()
    for index in range(3000, len(clean)):
        clean[index] += 0.05 * math.exp(-(index - 3000) / 1400)
    changed = [value * 0.92 for value in dry]
    for index in range(100, min(2600, len(changed))):
        changed[index] += 0.01 * math.sin(index * 0.13)
    paths = [folder / name for name in ["dry.wav", "clean.wav", "changed.wav"]]
    for path, samples in zip(paths, [dry, clean, changed]):
        write(path, samples)
    _, clean_fit = residuals.residual(comparison, comparison.read_pcm(paths[1]), comparison.read_pcm(paths[0]))
    _, changed_fit = residuals.residual(comparison, comparison.read_pcm(paths[2]), comparison.read_pcm(paths[0]))
    assert clean_fit["dryCancellationDB"] > 60
    assert changed_fit["dryCancellationDB"] < 60
    assert clean_fit["calibrationErrorRMS"] < changed_fit["calibrationErrorRMS"]
    assert abs(clean_fit["calibrationMilliseconds"] - 8) < 0.01
    # A processed capture longer than its dry file keeps that tail: the residual
    # must not be truncated to the dry length.
    tailed = clean + [0.02 * math.sin(index * 0.05) for index in range(12000)]
    tailed_path = folder / "tailed.wav"
    tailed_samples = (tailed + [0.0] * (len(dry) - len(tailed))) if len(tailed) < len(dry) else tailed
    with wave.open(str(tailed_path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(48000)
        output.writeframes(b"".join(struct.pack("<h", round(max(-1, min(1, value)) * 32767)) for value in tailed_samples))
    _, tailed_fit = residuals.residual(comparison, comparison.read_pcm(tailed_path), comparison.read_pcm(paths[0]))
    assert tailed_fit["subtractedFrames"] > len(dry), "the processed tail must not be truncated to the dry length"

print("PASS: wet-residual calibration distinguishes deterministic direct-path cancellation from changed source audio")

d = [0.4*math.sin(i*0.17) for i in range(4096)]
balanced, bad = residuals.residual(comparison,comparison.Audio(48000,[[0.5*v for v in d],[1.5*v for v in d]]),comparison.Audio(48000,[d,d]))
assert bad["dryCancellationDB"]>60 and all(abs(a-b)<1e-10 for a,b in zip(bad["channelDryGains"],[0.5,1.5]))
assert max(abs(v) for channel in balanced.channels for v in channel)<1e-10, "Per-channel gains must also be used for subtraction"
wet = d+[0.0]*1000+[0.3]+[0.0]*1000
remaining, info = residuals.residual(comparison,comparison.Audio(48000,[wet]),comparison.Audio(48000,[d]))
assert len(remaining.channels[0])>len(d) and max(remaining.channels[0][-2001:])>=0.3
