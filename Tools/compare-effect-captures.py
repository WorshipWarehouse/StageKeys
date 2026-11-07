#!/usr/bin/env python3
"""Compare matched Sunday Keys and StageKeys PCM WAV effect captures.

The program is intentionally dependency-free so it can run on release Macs.
It never claims algorithm identity: its output is a repeatable set of observed
audio differences for clean-room tuning of StageKeys DSP.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import wave
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Audio:
    rate: int
    channels: list[list[float]]


def read_pcm(path: Path) -> Audio:
    with wave.open(str(path), "rb") as wav:
        channels = wav.getnchannels()
        width = wav.getsampwidth()
        rate = wav.getframerate()
        frames = wav.getnframes()
        if wav.getcomptype() != "NONE" or width not in (2, 3, 4):
            raise ValueError(f"{path}: expected uncompressed 16/24/32-bit PCM WAV")
        raw = wav.readframes(frames)
    values: list[float] = []
    scale = float(1 << (width * 8 - 1))
    if width == 2:
        values = [v / scale for (v,) in struct.iter_unpack("<h", raw)]
    elif width == 4:
        values = [v / scale for (v,) in struct.iter_unpack("<i", raw)]
    else:
        for offset in range(0, len(raw), 3):
            value = int.from_bytes(raw[offset : offset + 3], "little", signed=True)
            values.append(value / scale)
    return Audio(rate, [values[c::channels] for c in range(channels)])


def mono(audio: Audio) -> list[float]:
    if len(audio.channels) == 1:
        return audio.channels[0]
    return [sum(frame) / len(audio.channels) for frame in zip(*audio.channels)]


def rms(samples: list[float]) -> float:
    return math.sqrt(sum(v * v for v in samples) / max(1, len(samples)))


def onset(samples: list[float], threshold: float = 1e-5) -> int | None:
    peak = max((abs(v) for v in samples), default=0.0)
    gate = max(threshold, peak * 1e-4)
    return next((i for i, value in enumerate(samples) if abs(value) >= gate), None)


def correlation(left: list[float], right: list[float]) -> float:
    numerator = sum(a * b for a, b in zip(left, right))
    denominator = math.sqrt(sum(a * a for a in left) * sum(b * b for b in right))
    return numerator / denominator if denominator else 0.0


def spectral_centroid(samples: list[float], rate: int) -> float:
    # A bounded direct DFT is sufficient for a stable comparison metric and
    # avoids adding a runtime dependency to the repository.
    count = min(len(samples), 4096)
    if count < 32:
        return 0.0
    start = (len(samples) - count) // 2
    block = samples[start : start + count]
    bins = min(512, count // 2)
    weighted = total = 0.0
    for k in range(1, bins):
        real = imag = 0.0
        step = -2.0 * math.pi * k / count
        for n, value in enumerate(block):
            windowed = value * (0.5 - 0.5 * math.cos(2.0 * math.pi * n / (count - 1)))
            real += windowed * math.cos(step * n)
            imag += windowed * math.sin(step * n)
        magnitude = math.hypot(real, imag)
        frequency = k * rate / count
        weighted += frequency * magnitude
        total += magnitude
    return weighted / total if total else 0.0


def decay_seconds(samples: list[float], rate: int) -> float | None:
    if not samples:
        return None
    peak_index = max(range(len(samples)), key=lambda i: abs(samples[i]))
    peak = abs(samples[peak_index])
    if peak == 0:
        return None
    target = peak * 0.001  # -60 dB amplitude
    window = max(1, rate // 100)
    for index in range(peak_index, len(samples) - window, window):
        if rms(samples[index : index + window]) <= target:
            return (index - peak_index) / rate
    return None


def describe(reference: Audio, candidate: Audio) -> dict[str, object]:
    if reference.rate != candidate.rate:
        raise ValueError("sample rates differ; resample captures before comparison")
    if len(reference.channels) != len(candidate.channels):
        raise ValueError("channel counts differ")
    length = min(len(reference.channels[0]), len(candidate.channels[0]))
    ref = mono(Audio(reference.rate, [c[:length] for c in reference.channels]))
    cand = mono(Audio(candidate.rate, [c[:length] for c in candidate.channels]))
    ref_energy = sum(v * v for v in ref)
    gain = sum(a * b for a, b in zip(ref, cand)) / ref_energy if ref_energy else 1.0
    aligned = [gain * value for value in ref]
    error = [a - b for a, b in zip(aligned, cand)]
    ref_onset, cand_onset = onset(ref), onset(cand)
    result: dict[str, object] = {
        "sampleRate": reference.rate,
        "channels": len(reference.channels),
        "framesCompared": length,
        "referencePeak": max((abs(v) for v in ref), default=0.0),
        "candidatePeak": max((abs(v) for v in cand), default=0.0),
        "referenceRMS": rms(ref),
        "candidateRMS": rms(cand),
        "candidateToReferenceGainDB": 20 * math.log10(max(rms(cand), 1e-12) / max(rms(ref), 1e-12)),
        "correlation": correlation(ref, cand),
        "leastSquaresReferenceGain": gain,
        "gainAlignedErrorRMS": rms(error),
        "gainAlignedErrorDBFS": 20 * math.log10(max(rms(error), 1e-12)),
        "referenceOnsetFrame": ref_onset,
        "candidateOnsetFrame": cand_onset,
        "onsetDeltaMilliseconds": None if ref_onset is None or cand_onset is None else (cand_onset - ref_onset) * 1000 / reference.rate,
        "referenceDecay60Seconds": decay_seconds(ref, reference.rate),
        "candidateDecay60Seconds": decay_seconds(cand, candidate.rate),
        "referenceCentroidHz": spectral_centroid(ref, reference.rate),
        "candidateCentroidHz": spectral_centroid(cand, candidate.rate),
    }
    if len(reference.channels) == 2:
        result["referenceStereoCorrelation"] = correlation(reference.channels[0][:length], reference.channels[1][:length])
        result["candidateStereoCorrelation"] = correlation(candidate.channels[0][:length], candidate.channels[1][:length])
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("reference", type=Path, help="Sunday Keys reference WAV")
    parser.add_argument("candidate", type=Path, help="StageKeys candidate WAV")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = describe(read_pcm(args.reference), read_pcm(args.candidate))
    payload = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(payload)
    else:
        print(payload, end="")


if __name__ == "__main__":
    main()
