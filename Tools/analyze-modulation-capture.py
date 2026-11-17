#!/usr/bin/env python3
"""Measure a free-running chorus/flanger delay trajectory without phase matching."""
import argparse
import importlib.util
import json
import math
from pathlib import Path
import sys


def comparator():
    path = Path(__file__).with_name("compare-effect-captures.py")
    spec = importlib.util.spec_from_file_location("stagekeys_capture_compare", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def trajectory(dry, processed, minimum_ms, maximum_ms, step_frames=2048, downsample=8):
    module = comparator()
    dry_mono, wet_mono = module.mono(dry), module.mono(processed)
    dry_onset, wet_onset = module.onset(dry_mono), module.onset(wet_mono)
    if dry_onset is None or wet_onset is None:
        raise ValueError("both captures need a detectable onset")
    # Trim both captures at one shared frame, not at their own onsets: aligning
    # each onset independently would erase exactly the processing delay this
    # tracker is asked to measure.
    origin = min(dry_onset, wet_onset)
    dry_mono = dry_mono[origin:]
    wet_mono = wet_mono[origin:]
    low=max(0,round(minimum_ms*dry.rate/1000/downsample))
    high=max(low+1,round(maximum_ms*dry.rate/1000/downsample))
    window=512
    points=[]
    previous_lag=None
    saturated=0
    for original in range(high*downsample, min(len(dry_mono),len(wet_mono))-window*downsample,step_frames):
        wet=[wet_mono[original+i*downsample] for i in range(window)]
        wet_energy=sum(v*v for v in wet)
        if wet_energy < 1e-7: continue
        best=None
        # Sustained piano tones have many nearly equivalent correlation peaks
        # one wavelength apart. Follow the physical delay continuously instead
        # of allowing the tracker to jump between those peaks; even a 5 Hz,
        # 10 ms modulation moves by less than this between 2048-frame windows.
        search_low=low if previous_lag is None else max(low,previous_lag-8)
        search_high=high if previous_lag is None else min(high,previous_lag+8)
        for lag in range(search_low,search_high+1):
            source=original-lag*downsample
            dry_window=[dry_mono[source+i*downsample] for i in range(window)]
            energy=sum(v*v for v in dry_window)
            if energy < 1e-7: continue
            score=sum(a*b for a,b in zip(wet,dry_window))/math.sqrt(wet_energy*energy)
            if best is None or abs(score)>abs(best[0]):best=(score,lag)
        if best is not None:
            if previous_lag is not None and ((search_low > low and best[1] == search_low) or (search_high < high and best[1] == search_high)):
                saturated += 1
            previous_lag=best[1]
            points.append((original/dry.rate,best[1]*downsample*1000/dry.rate,best[0]))
    if len(points)<12:raise ValueError("capture has too little sustained correlated audio")
    if saturated > max(2,len(points)//10):
        raise ValueError("delay tracker saturated its continuity window; reduce step size or increase the search window")
    return points


def _solve3(matrix, rhs):
    """Solve a 3x3 linear system with Cramer's rule; None when it is singular."""
    (a, b, c), (d, e, f), (g, h, i) = matrix

    def determinant(m):
        (a, b, c), (d, e, f), (g, h, i) = m
        return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)

    det = determinant(matrix)
    if abs(det) < 1e-12:
        return None
    return (determinant([(rhs[0], b, c), (rhs[1], e, f), (rhs[2], h, i)]) / det,
            determinant([(a, rhs[0], c), (d, rhs[1], f), (g, rhs[2], i)]) / det,
            determinant([(a, b, rhs[0]), (d, e, rhs[1]), (g, h, rhs[2])]) / det)


def fit(points):
    times = [p[0] for p in points]
    values = [p[1] for p in points]
    if len(points) < 12:
        raise ValueError("capture has too few trajectory points for a fit")
    count = len(values)
    best = None
    for index in range(50, 5001):
        hz = index / 1000
        s = [math.sin(2 * math.pi * hz * t) for t in times]
        c = [math.cos(2 * math.pi * hz * t) for t in times]
        # Offset and the sine/cosine pair are fitted jointly. Centring the values
        # first fixes the offset to the sample mean, which is not the fitted
        # centre whenever the capture covers only part of a modulation cycle.
        sum_s, sum_c = sum(s), sum(c)
        sum_ss = sum(v * v for v in s)
        sum_cc = sum(v * v for v in c)
        sum_sc = sum(x * y for x, y in zip(s, c))
        matrix = [[count, sum_s, sum_c], [sum_s, sum_ss, sum_sc], [sum_c, sum_sc, sum_cc]]
        rhs = [sum(values),
               sum(v * x for v, x in zip(values, s)),
               sum(v * x for v, x in zip(values, c))]
        solved = _solve3(matrix, rhs)
        if solved is None:
            continue
        offset, a, b = solved
        error = sum((v - offset - a * x - b * y) ** 2 for v, x, y in zip(values, s, c)) / count
        if best is None or error < best[0]:
            best = (error, hz, offset, math.hypot(a, b))
    if best is None:
        raise ValueError("trajectory cannot support a fitted modulation centre and depth")
    error, hz, offset, amplitude = best
    return {"frequencyHz":hz,"centerDelayMilliseconds":offset,"delayDepthMilliseconds":amplitude,
            "fitErrorMillisecondsRMS":math.sqrt(error),"points":len(points),
            "medianAbsoluteCorrelation":sorted(abs(p[2]) for p in points)[len(points)//2]}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("dry",type=Path);parser.add_argument("processed",type=Path)
    parser.add_argument("--minimum-delay-ms",type=float,default=0.2)
    parser.add_argument("--maximum-delay-ms",type=float,default=35)
    parser.add_argument("--output",type=Path)
    args=parser.parse_args();module=comparator()
    dry=module.read_pcm(args.dry);processed=module.read_pcm(args.processed)
    if dry.rate!=processed.rate or len(dry.channels)!=len(processed.channels):raise ValueError("capture formats differ")
    report=fit(trajectory(dry,processed,args.minimum_delay_ms,args.maximum_delay_ms))
    report.update({"sampleRate":dry.rate,"minimumDelayMilliseconds":args.minimum_delay_ms,"maximumDelayMilliseconds":args.maximum_delay_ms})
    payload=json.dumps(report,indent=2,sort_keys=True)+"\n"
    if args.output:args.output.write_text(payload)
    else:print(payload,end="")


if __name__=="__main__":main()
