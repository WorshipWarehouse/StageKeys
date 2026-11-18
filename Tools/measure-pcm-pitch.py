#!/usr/bin/env python3
"""Offline pitch evidence for declared PCM notes; not a fidelity/parity metric."""
import argparse
import importlib.util
import json
import math
from pathlib import Path
import sys


def estimate(samples, rate):
    """Cumulative-mean normalized difference (YIN), bounded 80–1200 Hz."""
    # Preserve the original rate: stride-only decimation aliases upper harmonics.
    # Search the first credible period, including above the admitted pitch range,
    # so an out-of-range pure tone is refused instead of folded to a subharmonic.
    signal=samples[:4096]
    low=2;high=int(rate/80)
    count=min(2048,len(signal)-high)
    if count<512 or sum(x*x for x in signal[:count])/count<1e-10:
        return None
    differences=[0.0]*(high+1)
    for lag in range(1,high+1):
        differences[lag]=sum((signal[i]-signal[i+lag])**2 for i in range(count))
    normalized=[1.0]*(high+1);total=0.0
    for lag in range(1,high+1):
        total+=differences[lag]
        normalized[lag]=differences[lag]*lag/total if total>0 else 1.0
    lag=low
    while lag<high:
        if normalized[lag]<0.12:
            while lag+1<high and normalized[lag+1]<normalized[lag]:lag+=1
            left,centre,right=normalized[lag-1:lag+2]
            curvature=left-2*centre+right
            fraction=(left-right)/(2*curvature) if abs(curvature)>1e-12 else 0.0
            frequency=rate/(lag+max(-.5,min(.5,fraction)))
            if not 80<=frequency<=1200:
                return None
            return {"frequencyHz":frequency,"confidence":1-centre}
        lag+=1
    return None


def read_audio(path):
    spec=importlib.util.spec_from_file_location('pcm_reader',Path(__file__).with_name('compare-effect-captures.py'))
    module=importlib.util.module_from_spec(spec);sys.modules[spec.name]=module;spec.loader.exec_module(module)
    return module.read_pcm(path)


def describe(path, note):
    audio=read_audio(path)
    expected=440*2**((note-69)/12)
    channels=[]
    for channel in audio.channels:
        windows=[]
        for seconds in [.08,.3,.6]:
            start=round(seconds*audio.rate)
            result=estimate(channel[start:start+round(audio.rate*.5)],audio.rate)
            if result is not None:
                result['startSeconds']=seconds
                result['centsFromDeclaredNote']=1200*math.log2(result['frequencyHz']/expected)
                windows.append(result)
        channels.append(windows)
    return {"frames":len(audio.channels[0]),"sampleRate":audio.rate,"declaredMIDINote":note,"expectedHz":expected,"channels":channels}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('audio',type=Path);parser.add_argument('--note',type=int,required=True);parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    if not 0<=args.note<=127:parser.error('note must be 0–127')
    payload=json.dumps(describe(args.audio,args.note),indent=2,sort_keys=True)+'\n'
    if args.output:args.output.write_text(payload)
    else:print(payload,end='')


if __name__=='__main__':main()
