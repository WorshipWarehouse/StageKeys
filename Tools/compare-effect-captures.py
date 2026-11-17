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
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Audio:
    rate: int
    channels: list[list[float]]


def read_pcm(path: Path) -> Audio:
    channels, width, rate, raw, floating = read_extensible_wave(path)
    values: list[float] = []
    scale = float(1 << (width * 8 - 1))
    if floating and width == 4:
        values = [v for (v,) in struct.iter_unpack("<f", raw)]
    elif width == 2:
        values = [v / scale for (v,) in struct.iter_unpack("<h", raw)]
    elif width == 4:
        values = [v / scale for (v,) in struct.iter_unpack("<i", raw)]
    else:
        for offset in range(0, len(raw), 3):
            value = int.from_bytes(raw[offset : offset + 3], "little", signed=True)
            values.append(value / scale)
    return Audio(rate, [values[c::channels] for c in range(channels)])


def read_extensible_wave(path: Path) -> tuple[int, int, int, bytes, bool]:
    data = path.read_bytes()
    if len(data) < 12 or data[:4] not in (b"RIFF", b"RF64") or data[8:12] != b"WAVE":
        raise ValueError(f"{path}: not a RIFF/RF64 WAVE file")
    offset, fmt, samples = 12, None, None
    while offset + 8 <= len(data):
        kind, size = data[offset : offset + 4], struct.unpack_from("<I", data, offset + 4)[0]
        payload = data[offset + 8 : offset + 8 + size]
        if kind == b"fmt ": fmt = payload
        elif kind == b"data": samples = payload
        offset += 8 + size + (size & 1)
    if fmt is None or samples is None or len(fmt) < 16:
        raise ValueError(f"{path}: missing fmt or data chunk")
    tag, channels, rate, _, _, bits = struct.unpack_from("<HHIIHH", fmt)
    floating = tag == 3
    if tag == 0xFFFE and len(fmt) >= 40:
        # WAVE_FORMAT_EXTENSIBLE stores the actual format tag as the first
        # 16-bit word of the 16-byte subtype GUID. 1=PCM, 3=IEEE float.
        subtype = struct.unpack_from("<H", fmt, 24)[0]
        floating = subtype == 3
        tag = subtype
    width = bits // 8
    if tag not in (1, 3) or width not in (2, 3, 4) or channels < 1:
        raise ValueError(f"{path}: unsupported WAVE format tag {tag}, {bits} bits")
    return channels, width, rate, samples, floating


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
    # Spread a bounded number of bins across the whole Nyquist range. Stopping at
    # 512 low bins excluded everything at and above 6 kHz for a 4096-sample block
    # at 48 kHz, so a high tone contributed only leakage to the centroid.
    limit = count // 2
    bin_count = min(256, max(1, limit - 1))
    bins = sorted({max(1, min(limit - 1, round(index * (limit - 1) / bin_count)))
                   for index in range(1, bin_count + 1)})
    weighted = total = 0.0
    for k in bins:
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
    quiet = None
    for index in range(peak_index, len(samples) - window, window):
        if rms(samples[index : index + window]) <= target:
            quiet = index
            break
    if quiet is None:
        return None
    # A quiet gap can sit between the direct sound and a later echo, so decay is
    # only established when everything from that gap to the end stays below the
    # threshold; a capture that ends first reports no decay instead of the gap.
    if rms(samples[quiet:]) > target:
        return None
    return (quiet - peak_index) / rate


def describe(reference: Audio, candidate: Audio, align_onsets: bool = False) -> dict[str, object]:
    if reference.rate != candidate.rate:
        raise ValueError("sample rates differ; resample captures before comparison")
    if len(reference.channels) != len(candidate.channels):
        raise ValueError("channel counts differ")
    raw_reference_onset, raw_candidate_onset = onset(mono(reference)), onset(mono(candidate))
    capture_offset = None
    if align_onsets and raw_reference_onset is not None and raw_candidate_onset is not None:
        capture_offset = (raw_candidate_onset - raw_reference_onset) * 1000 / reference.rate
        reference = Audio(reference.rate, [channel[raw_reference_onset:] for channel in reference.channels])
        candidate = Audio(candidate.rate, [channel[raw_candidate_onset:] for channel in candidate.channels])
    length = min(len(reference.channels[0]), len(candidate.channels[0]))
    ref = mono(Audio(reference.rate, [c[:length] for c in reference.channels]))
    cand = mono(Audio(candidate.rate, [c[:length] for c in candidate.channels]))
    ref_energy = sum(v * v for v in ref)
    gain = sum(a * b for a, b in zip(ref, cand)) / ref_energy if ref_energy else 1.0
    aligned = [gain * value for value in ref]
    error = [a - b for a, b in zip(aligned, cand)]
    # Tail metrics use each capture's own aligned samples: truncating to the
    # shorter capture would hide an echo only the longer one carries.
    ref_tail = mono(reference)
    cand_tail = mono(candidate)
    ref_onset, cand_onset = onset(ref), onset(cand)
    result: dict[str, object] = {
        "sampleRate": reference.rate,
        "channels": len(reference.channels),
        "framesCompared": length,
        "captureFrames": {"reference": len(reference.channels[0]), "candidate": len(candidate.channels[0])},
        "captureStartOffsetMilliseconds": capture_offset,
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
        "referenceDecay60Seconds": decay_seconds(ref_tail, reference.rate),
        "candidateDecay60Seconds": decay_seconds(cand_tail, candidate.rate),
        "referenceCentroidHz": spectral_centroid(ref_tail, reference.rate),
        "candidateCentroidHz": spectral_centroid(cand_tail, candidate.rate),
    }
    # A swapped stereo pair downmixes to the same mono signal, so each channel is
    # measured on its own; the mono metrics stay as summaries.
    channel_metrics = []
    for index, (reference_channel, candidate_channel) in enumerate(zip(reference.channels, candidate.channels)):
        pair_reference = reference_channel[:length]
        pair_candidate = candidate_channel[:length]
        pair_energy = sum(v * v for v in pair_reference)
        pair_gain = sum(a * b for a, b in zip(pair_reference, pair_candidate)) / pair_energy if pair_energy else 1.0
        pair_error = [pair_gain * a - b for a, b in zip(pair_reference, pair_candidate)]
        channel_metrics.append({
            "channel": index,
            "referenceRMS": rms(pair_reference),
            "candidateRMS": rms(pair_candidate),
            "correlation": correlation(pair_reference, pair_candidate),
            "leastSquaresReferenceGain": pair_gain,
            "gainAlignedErrorRMS": rms(pair_error),
            "gainAlignedErrorDBFS": 20 * math.log10(max(rms(pair_error), 1e-12)),
        })
    result["channelMetrics"] = channel_metrics
    if len(reference.channels) == 2:
        result["referenceStereoCorrelation"] = correlation(reference.channels[0][:length], reference.channels[1][:length])
        result["candidateStereoCorrelation"] = correlation(candidate.channels[0][:length], candidate.channels[1][:length])
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("reference", type=Path, help="Sunday Keys reference WAV")
    parser.add_argument("candidate", type=Path, help="StageKeys candidate WAV")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--align-onset", action="store_true", help="trim both captures to their first detected dry onset")
    args = parser.parse_args()
    report = describe(read_pcm(args.reference), read_pcm(args.candidate), align_onsets=args.align_onset)
    payload = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(payload)
    else:
        print(payload, end="")


if __name__ == "__main__":
    main()
