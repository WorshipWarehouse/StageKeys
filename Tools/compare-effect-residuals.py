#!/usr/bin/env python3
"""Compare wet residuals after removing the matched dry performance.

This is useful when an effect exposes independent dry/wet levels. Captures are
trimmed to their first dry onset before subtraction; no resampling is performed.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import sys


def load_comparator():
    path = Path(__file__).with_name("compare-effect-captures.py")
    spec = importlib.util.spec_from_file_location("stagekeys_capture_compare", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def residual(module, processed, dry):
    processed_onset = module.onset(module.mono(processed))
    dry_onset = module.onset(module.mono(dry))
    if processed_onset is None or dry_onset is None:
        raise ValueError("both processed and dry captures must contain a detectable onset")
    # Fit only the first 52 ms, before the measured PrimaVerb wet onset. This
    # removes tiny capture gain differences without fitting away reverb energy.
    processed_mono = module.mono(processed)
    dry_mono = module.mono(dry)
    calibration_frames = min(2500, len(processed_mono) - processed_onset, len(dry_mono) - dry_onset)
    best = None
    for lag in range(-32, 33):
        processed_start = processed_onset + max(lag, 0)
        dry_start = dry_onset + max(-lag, 0)
        count = min(calibration_frames, len(processed_mono) - processed_start, len(dry_mono) - dry_start)
        processed_slice = processed_mono[processed_start:processed_start + count]
        dry_slice = dry_mono[dry_start:dry_start + count]
        dry_energy = sum(value * value for value in dry_slice)
        gain = sum(a * b for a, b in zip(processed_slice, dry_slice)) / dry_energy if dry_energy else 1.0
        error = sum((a - gain * b) ** 2 for a, b in zip(processed_slice, dry_slice)) / max(1, count)
        if best is None or error < best[0]:
            best = error, lag, gain
    _, lag, dry_gain = best
    processed_start = processed_onset + max(lag, 0)
    dry_start = dry_onset + max(-lag, 0)
    length = min(len(processed.channels[0]) - processed_start, len(dry.channels[0]) - dry_start)
    channels = []
    for processed_channel, dry_channel in zip(processed.channels, dry.channels):
        channels.append([
            processed_channel[processed_start + index] - dry_gain * dry_channel[dry_start + index]
            for index in range(length)
        ])
    return module.Audio(processed.rate, channels), {
        "processedOnsetFrame": processed_onset,
        "dryOnsetFrame": dry_onset,
        "dryAlignmentLagFrames": lag,
        "dryGain": dry_gain,
        "calibrationFrames": calibration_frames,
        "subtractedFrames": length,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("reference", type=Path)
    parser.add_argument("reference_dry", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("candidate_dry", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    module = load_comparator()
    reference = module.read_pcm(args.reference)
    reference_dry = module.read_pcm(args.reference_dry)
    candidate = module.read_pcm(args.candidate)
    candidate_dry = module.read_pcm(args.candidate_dry)
    rates = {audio.rate for audio in [reference, reference_dry, candidate, candidate_dry]}
    channel_counts = {len(audio.channels) for audio in [reference, reference_dry, candidate, candidate_dry]}
    if len(rates) != 1 or len(channel_counts) != 1:
        raise ValueError("all captures must have matching sample rates and channel counts")
    reference_wet, reference_alignment = residual(module, reference, reference_dry)
    candidate_wet, candidate_alignment = residual(module, candidate, candidate_dry)
    report = module.describe(reference_wet, candidate_wet, align_onsets=False)
    report["referenceDrySubtraction"] = reference_alignment
    report["candidateDrySubtraction"] = candidate_alignment
    payload = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(payload)
    else:
        print(payload, end="")


if __name__ == "__main__":
    main()
