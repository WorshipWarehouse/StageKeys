#!/usr/bin/env python3
"""Compare declared wet impulse-response tails, not arbitrary musical captures.

Independent octave-band estimates; no ISO measurement or sonic-parity claim.
Capture both responses with identical excitation, route, gain and effect settings.
The declared start is the end of excitation in each aligned capture.
"""
import argparse
import importlib.util
import json
import math
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('effect_capture', Path(__file__).with_name('compare-effect-captures.py'))
capture = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = capture
spec.loader.exec_module(capture)


def bandpass(samples, rate, frequency):
    # RBJ constant-peak bandpass, Q=sqrt(2), approximately one octave wide.
    w = 2 * math.pi * frequency / rate
    alpha = math.sin(w) / (2 * math.sqrt(2))
    b0, b2 = alpha / (1 + alpha), -alpha / (1 + alpha)
    a1, a2 = -2 * math.cos(w) / (1 + alpha), (1 - alpha) / (1 + alpha)
    x1 = x2 = y1 = y2 = 0.0
    output = []
    for x in samples:
        y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
        output.append(y)
        x2, x1, y2, y1 = x1, x, y1, y
    return output


def estimate(channels, rate, frequency):
    if not channels or not channels[0]:
        raise ValueError('empty response')
    energy = [0.0] * len(channels[0])
    for channel in channels:
        for i, value in enumerate(bandpass(channel, rate, frequency)):
            energy[i] += value * value
    # Power addition preserves stereo anti-phase responses instead of cancelling.
    step = max(1, round(rate * .005))
    bins = [sum(energy[i:i + step]) for i in range(0, len(energy), step)]
    total, peak = sum(bins), max(bins)
    result = {'energy': total / rate, 't20EstimatedT60Seconds': None,
              'fitR2': None, 'status': 'insufficient range'}
    if total < 1e-16 or peak < 1e-16:
        result['status'] = 'silent'
        return result
    # Require the final 100 ms to settle. A cut-off capture otherwise produces
    # a deceptively steep reverse-integrated curve and a false short decay.
    terminal = sum(energy[-max(1, round(rate * .1)):]) / min(len(energy), max(1, round(rate * .1)))
    peak_power = peak / step
    result['terminalToPeakDB'] = 10 * math.log10(max(terminal / peak_power, 1e-30))
    if result['terminalToPeakDB'] > -60:
        result['status'] = 'unsettled or noise limited'
        return result
    # Digital padding can follow a cut-off before the final 100 ms. A sharp
    # late power drop above the established floor is not evidence of settling.
    # Reject conservatively; a sparse tail may need a different capture/probe.
    power_step = max(1, round(rate * .02))
    power_bins = [sum(energy[i:i + power_step]) for i in range(0, len(energy), power_step)]
    power_peak = max(power_bins)
    for before, after in zip(power_bins[1:], power_bins[2:]):
        if before > power_peak * 1e-6 and after < before * 10 ** (-12 / 10):
            result['status'] = 'abrupt cutoff or sparse tail'
            return result
    integrated, tail = [], 0.0
    for value in reversed(bins):
        tail += value
        integrated.append(tail)
    integrated.reverse()
    points = [(i * step / rate, 10 * math.log10(max(v / total, 1e-30))) for i, v in enumerate(integrated)]
    duration, quality = fit_decay(points)
    result['fitR2'] = quality
    if duration is None:
        result['status'] = 'insufficient coverage or non-exponential fit'
        return result
    result.update(t20EstimatedT60Seconds=duration, status='estimated')
    return result


def fit_decay(points):
    fit = [(t, db) for t, db in points if -25 <= db <= -5]
    # A T20 estimate needs observations near both ends, not six points
    # concentrated in a tiny part of the intended 20 dB interval.
    if len(fit) < 6 or fit[0][1] < -6 or fit[-1][1] > -24 or fit[0][1] - fit[-1][1] < 18:
        return None, None
    tx, ty = sum(t for t, _ in fit) / len(fit), sum(db for _, db in fit) / len(fit)
    xx = sum((t - tx) ** 2 for t, _ in fit)
    yy = sum((db - ty) ** 2 for _, db in fit)
    xy = sum((t - tx) * (db - ty) for t, db in fit)
    if xx <= 0 or yy <= 0:
        return None, None
    slope, r2 = xy / xx, xy * xy / (xx * yy)
    return (-60 / slope if slope < 0 and r2 >= .98 else None), r2


def compare(reference, candidate, tail_start):
    if reference.rate != candidate.rate or len(reference.channels) != len(candidate.channels):
        raise ValueError('matched sample rates and channel counts required')
    if not 8000 <= reference.rate <= 96000 or len(reference.channels) not in (1, 2):
        raise ValueError('only mono/stereo responses at 8–96 kHz are supported')
    for audio in (reference, candidate):
        if not audio.channels or not audio.channels[0] or len(audio.channels[0]) > audio.rate * 120:
            raise ValueError('choose nonempty responses no longer than 120 seconds')
        if any(len(c) != len(audio.channels[0]) for c in audio.channels):
            raise ValueError('channel lengths differ')
        if any(not math.isfinite(v) for c in audio.channels for v in c):
            raise ValueError('nonfinite PCM')
    if not math.isfinite(tail_start) or tail_start < 0:
        raise ValueError('invalid excitation-end time')
    start = round(tail_start * reference.rate)
    if any(start >= len(a.channels[0]) for a in (reference, candidate)):
        raise ValueError('excitation end must precede both tails')
    rows = []
    for frequency in (125, 250, 500, 1000, 2000, 4000, 8000):
        if frequency * math.sqrt(2) >= reference.rate / 2:
            continue
        a, b = [estimate([c[start:] for c in audio.channels], audio.rate, frequency) for audio in (reference, candidate)]
        valid = a['status'] == b['status'] == 'estimated'
        rows.append({'centerHz': frequency, 'reference': a, 'candidate': b,
                     'energyGainDeltaDB': 10 * math.log10(b['energy'] / a['energy']) if min(a['energy'], b['energy']) > 1e-16 else None,
                     'estimatedT60DeltaSeconds': b['t20EstimatedT60Seconds'] - a['t20EstimatedT60Seconds'] if valid else None})
    return {'schemaVersion': 1, 'rate': reference.rate, 'channels': len(reference.channels),
            'excitationEndSeconds': tail_start, 'bands': rows,
            'scope': 'Wet impulse-response estimates; no source match, ISO certification or musical-envelope equivalence inferred.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reference', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--excitation-end', type=float, required=True)
    args = parser.parse_args()
    for path in (args.reference, args.candidate):
        if path.stat().st_size > 64 << 20:
            parser.error('capture exceeds 64 MiB')
    try:
        report = compare(capture.read_pcm(args.reference), capture.read_pcm(args.candidate), args.excitation_end)
    except ValueError as error:
        parser.error(str(error))
    print(json.dumps(report, indent=2, allow_nan=False))


if __name__ == '__main__':
    main()
