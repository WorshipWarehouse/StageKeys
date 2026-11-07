#!/usr/bin/env python3
import importlib.util
import math
import struct
import sys
import tempfile
import wave
from pathlib import Path

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("comparison", root / "Tools" / "compare-effect-captures.py")
comparison = importlib.util.module_from_spec(spec)
assert spec.loader
sys.modules[spec.name] = comparison
spec.loader.exec_module(comparison)


def write(path: Path, samples: list[float], rate: int = 48000) -> None:
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(b"".join(struct.pack("<h", max(-32768, min(32767, round(v * 32767)))) for v in samples))


with tempfile.TemporaryDirectory() as directory:
    directory = Path(directory)
    reference = [0.0] * 96 + [0.4 * math.sin(i * 0.005) * math.exp(-i / 4000) for i in range(12000)]
    candidate = [0.0] * 120 + [0.2 * math.sin(i * 0.005) * math.exp(-i / 4000) for i in range(12000)]
    a, b = directory / "a.wav", directory / "b.wav"
    write(a, reference)
    write(b, candidate)
    report = comparison.describe(comparison.read_pcm(a), comparison.read_pcm(b))
    assert abs(report["candidateToReferenceGainDB"] + 6.0206) < 0.05
    assert abs(report["onsetDeltaMilliseconds"] - 0.5) < 0.03
    assert report["correlation"] > 0.99
    assert report["gainAlignedErrorDBFS"] < -35
print("PASS: matched capture metrics report gain, onset, correlation and aligned error")
