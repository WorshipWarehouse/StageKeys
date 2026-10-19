#!/usr/bin/env python3
"""Compare dry MIDI velocity captures without retaining or modifying source audio.
Requires numpy. Reference is the changed curve; baseline is the neutral curve.
Default sequence: velocities 38,64,83,102, each at notes 60,74,86.
"""
import argparse
import json
import struct
from pathlib import Path
import numpy as np


def read_wave(path):
    data = Path(path).read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError("Expected a little-endian RIFF WAVE recording")
    position, fmt, raw = 12, None, None
    while position + 8 <= len(data):
        tag = data[position:position + 4]
        length = struct.unpack_from("<I", data, position + 4)[0]
        start = position + 8
        if start + length > len(data):
            raise ValueError("Truncated WAVE chunk")
        if tag == b"fmt ":
            fmt = data[start:start + length]
        elif tag == b"data":
            raw = data[start:start + length]
        position = start + length + length % 2
    if fmt is None or len(fmt) < 16 or raw is None:
        raise ValueError("Missing WAVE format or audio")
    kind, channels, rate, _, _, bits = struct.unpack_from("<HHIIHH", fmt)
    if kind == 65534:
        if len(fmt) < 40:
            raise ValueError("Truncated extensible format")
        kind = struct.unpack_from("<H", fmt, 24)[0]
    if channels not in (1, 2) or rate not in (44100, 48000, 88200, 96000):
        raise ValueError("Use mono/stereo recordings at a supported audio rate")
    if kind == 3 and bits in (32, 64):
        samples = np.frombuffer(raw, dtype="<f4" if bits == 32 else "<f8").astype(float)
    elif kind == 1 and bits in (16, 32):
        samples = np.frombuffer(raw, dtype="<i2" if bits == 16 else "<i4").astype(float) / 2 ** (bits - 1)
    elif kind == 1 and bits == 24:
        packed = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        values = packed[:, 0] | packed[:, 1] << 8 | packed[:, 2] << 16
        samples = np.where(values & 0x800000, values - 0x1000000, values) / 8388608
    else:
        raise ValueError("Unsupported PCM/float format")
    if not np.isfinite(samples).all() or not len(samples) or np.max(abs(samples)) >= 1:
        raise ValueError("Empty, nonfinite or potentially clipped recording")
    return rate, samples.reshape(-1, channels)


def onsets(samples, rate, count, threshold):
    block = rate // 100
    level = np.max(abs(samples), axis=1)
    energy = np.sqrt(np.mean(np.pad(level, (0, -len(level) % block)).reshape(-1, block) ** 2, axis=1))
    events = []
    for i, value in enumerate(energy):
        if value > threshold and (i == 0 or energy[i - 1] <= threshold) and (not events or i - events[-1] > 70):
            events.append(i)
    if len(events) != count:
        raise ValueError(f"Expected {count} isolated notes, detected {len(events)}; check sequence, threshold and keyboard input")
    return [i * block for i in events]


def compare(reference, baseline, notes, velocities, threshold):
    rate, first = read_wave(reference)
    second_rate, second = read_wave(baseline)
    if rate != second_rate or first.shape[1] != second.shape[1]:
        raise ValueError("Recordings must have matching rate and channel count; this tool never resamples")
    sequence = [(note, velocity) for velocity in velocities for note in notes]
    first_events = onsets(first, rate, len(sequence), threshold)
    second_events = onsets(second, rate, len(sequence), threshold)
    rows = []
    for (note, velocity), first_on, second_on in zip(sequence, first_events, second_events):
        length = int(rate * .45)
        a, b = first[first_on:first_on + length], second[second_on:second_on + length]
        if len(a) != length or len(b) != length:
            raise ValueError("Recording ends before the comparison window")
        size = 1 << (2 * length - 1).bit_length()
        correlation = np.fft.irfft(np.fft.rfft(a.mean(axis=1), size) * np.conj(np.fft.rfft(b.mean(axis=1), size)), size)
        limit = rate // 20
        lag = int(np.argmax(np.r_[correlation[-limit:], correlation[:limit]])) - limit
        if lag >= 0:
            a, b = a[lag:], b[:len(a) - lag]
        else:
            a, b = a[:len(b) + lag], b[-lag:]
        a, b = a[int(rate * .05):int(rate * .35)], b[int(rate * .05):int(rate * .35)]
        a_energy, b_energy = np.sum(a * a), np.sum(b * b)
        if min(a_energy, b_energy) < 1e-12:
            raise ValueError("Insufficient signal for gain estimation")
        gain = np.sum(a * b) / b_energy
        if gain <= 0:
            raise ValueError("Polarity mismatch; a scalar amplitude correction is not established")
        rows.append(dict(note=note, velocity=velocity, changedToNeutralDB=float(20 * np.log10(gain)), normalizedResidual=float(np.sqrt(np.sum((a - gain * b) ** 2) / a_energy)), lagSamples=lag))
    return rows


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("--notes", default="60,74,86")
    parser.add_argument("--velocities", default="38,64,83,102")
    parser.add_argument("--threshold", type=float, default=.00005)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    notes, velocities = [list(map(int, values.split(","))) for values in (args.notes, args.velocities)]
    if not notes or not velocities or any(not 0 <= n <= 127 for n in notes) or any(not 1 <= v <= 127 for v in velocities) or not 0 < args.threshold < 1:
        parser.error("Invalid note, velocity or detection threshold")
    args.output.write_text(json.dumps(compare(args.reference, args.baseline, notes, velocities, args.threshold), indent=2) + "\n")
