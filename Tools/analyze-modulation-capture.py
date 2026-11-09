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
    dry_mono=dry_mono[dry_onset:];wet_mono=wet_mono[wet_onset:]
    low=max(0,round(minimum_ms*dry.rate/1000/downsample))
    high=max(low+1,round(maximum_ms*dry.rate/1000/downsample))
    window=512
    points=[]
    previous_lag=None
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
            previous_lag=best[1]
            points.append((original/dry.rate,best[1]*downsample*1000/dry.rate,best[0]))
    if len(points)<12:raise ValueError("capture has too little sustained correlated audio")
    return points


def fit(points):
    times=[p[0] for p in points];values=[p[1] for p in points]
    best=None
    for index in range(50,5001):
        hz=index/1000
        s=[math.sin(2*math.pi*hz*t) for t in times];c=[math.cos(2*math.pi*hz*t) for t in times]
        # Offset plus sine/cosine least squares; centered approximation is
        # sufficient across multi-cycle captures and avoids external packages.
        mean=sum(values)/len(values);center=[v-mean for v in values]
        a=sum(v*x for v,x in zip(center,s))/max(1e-12,sum(x*x for x in s))
        b=sum(v*x for v,x in zip(center,c))/max(1e-12,sum(x*x for x in c))
        error=sum((v-mean-a*x-b*y)**2 for v,x,y in zip(values,s,c))/len(values)
        if best is None or error<best[0]:best=(error,hz,mean,math.hypot(a,b))
    error,hz,mean,amplitude=best
    return {"frequencyHz":hz,"centerDelayMilliseconds":mean,"delayDepthMilliseconds":amplitude,
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
