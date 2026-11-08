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

print("PASS: wet-residual calibration distinguishes deterministic direct-path cancellation from changed source audio")
