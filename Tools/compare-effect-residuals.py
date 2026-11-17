#!/usr/bin/env python3
"""Compare wet residuals after removing the matched dry performance.

This is useful when an effect exposes independent dry/wet levels. Captures are
trimmed to their first dry onset before subtraction; no resampling is performed.
"""
import argparse
import importlib.util
import json
import math
from pathlib import Path
import sys


def load_comparator():
    path = Path(__file__).with_name("compare-effect-captures.py")
    spec = importlib.util.spec_from_file_location("stagekeys_capture_compare", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def residual(module, processed, dry, calibration_milliseconds=8.0):
    processed_onset = module.onset(module.mono(processed))
    dry_onset = module.onset(module.mono(dry))
    if processed_onset is None or dry_onset is None:
        raise ValueError("both processed and dry captures must contain a detectable onset")
    # Fit only a declared pre-wet window. The default is shorter than the
    # smallest observed PrimaVerb predelay, so early reflections are not
    # mistaken for a changed direct path.
    processed_mono = module.mono(processed)
    dry_mono = module.mono(dry)
    requested_frames = max(1, round(processed.rate * calibration_milliseconds / 1000))
    calibration_frames = min(requested_frames, len(processed_mono) - processed_onset, len(dry_mono) - dry_onset)
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
            best = error, lag, gain, count
    calibration_error, lag, dry_gain, calibration_count = best
    processed_start = processed_onset + max(lag, 0)
    dry_start = dry_onset + max(-lag, 0)
    length = min(len(processed.channels[0]) - processed_start, len(dry.channels[0]) - dry_start)
    channels = []
    for processed_channel, dry_channel in zip(processed.channels, dry.channels):
        channels.append([
            processed_channel[processed_start + index] - dry_gain * dry_channel[dry_start + index]
            for index in range(length)
        ])
    processed_start = processed_onset + max(lag, 0)
    processed_slice = processed_mono[processed_start:processed_start + calibration_count]
    processed_rms = math.sqrt(sum(value * value for value in processed_slice) / max(1, len(processed_slice)))
    error_rms = math.sqrt(calibration_error)
    cancellation_db = 20 * math.log10(processed_rms / max(error_rms, 1e-15)) if processed_rms else 0.0
    return module.Audio(processed.rate, channels), {
        "processedOnsetFrame": processed_onset,
        "dryOnsetFrame": dry_onset,
        "dryAlignmentLagFrames": lag,
        "dryGain": dry_gain,
        "calibrationFrames": calibration_count,
        "calibrationMilliseconds": calibration_count * 1000 / processed.rate,
        "calibrationErrorRMS": error_rms,
        "dryCancellationDB": cancellation_db,
        "subtractedFrames": length,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("reference", type=Path)
    parser.add_argument("reference_dry", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("candidate_dry", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--minimum-dry-cancellation-db", type=float, default=60.0,
                        help="reject a processed/dry pair whose fitted direct signal cancels by less than this many dB")
    parser.add_argument("--calibration-milliseconds", type=float, default=8.0,
                        help="direct-path fitting window; it must end before the effect's first wet output")
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
    if not math.isfinite(args.calibration_milliseconds) or not 0 < args.calibration_milliseconds <= 100:
        raise ValueError("calibration milliseconds must be finite and in (0, 100]")
    reference_wet, reference_alignment = residual(module, reference, reference_dry, args.calibration_milliseconds)
    candidate_wet, candidate_alignment = residual(module, candidate, candidate_dry, args.calibration_milliseconds)
    for label, alignment in [("reference", reference_alignment), ("candidate", candidate_alignment)]:
        if alignment["dryCancellationDB"] < args.minimum_dry_cancellation_db:
            raise ValueError(
                f"{label} processed/dry pair cancels by only "
                f"{alignment['dryCancellationDB']:.1f} dB before the wet onset; "
                "use a deterministic source and matched direct-path settings"
            )
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
