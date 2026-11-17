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
    # Apple's afconvert emits float WAV as WAVE_FORMAT_EXTENSIBLE. Exercise the
    # direct reader without relying on Python's integer-only wave decoder.
    extended = directory / "float.wav"
    payload = struct.pack("<4f", 0.0, 0.25, -0.5, 1.0)
    subtype = bytes.fromhex("0300000000001000800000aa00389b71")
    fmt = struct.pack("<HHIIHHH", 0xFFFE, 1, 48000, 192000, 4, 32, 22) + struct.pack("<HI", 32, 4) + subtype
    riff_size = 4 + 8 + len(fmt) + 8 + len(payload)
    extended.write_bytes(b"RIFF" + struct.pack("<I", riff_size) + b"WAVEfmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(payload)) + payload)
    decoded = comparison.read_pcm(extended)
    assert decoded.rate == 48000 and decoded.channels == [[0.0, 0.25, -0.5, 1.0]]
print("PASS: matched capture metrics report gain, onset, correlation and aligned error")

# A high tone must contribute its main energy to the centroid, not only leakage.
tone=[math.sin(2*math.pi*10000*i/48000) for i in range(4096)]
assert abs(comparison.spectral_centroid(tone,48000)-10000)<500, comparison.spectral_centroid(tone,48000)

# A quiet gap before a later echo is not the end of the decay; a capture that
# never settles reports no decay at all.
rate=48000
echo=[0.0]*(rate//2)
echo[0]=1.0
echo[rate//5]=0.5
assert comparison.decay_seconds(echo,rate)>0.2,"decay must follow the final echo, not the first quiet gap"
assert comparison.decay_seconds([1.0]*2000,rate) is None,"an unsettled capture has no established decay"
settling=[0.0]*(rate//2)
settling[0]=1.0
for i in range(1,rate//10):
    settling[i]=math.exp(-i/2000)
assert comparison.decay_seconds(settling,rate) is not None,"a settling capture must report a decay"
# Trailing silence must not move the centroid: the window comes from the loud part
# of the capture, not its middle, so the same tone reports the same frequency.
burst=[0.5*math.sin(2*math.pi*3000*i/rate) for i in range(4096)]
padded=burst+[0.0]*20000
assert abs(comparison.spectral_centroid(padded,rate)-comparison.spectral_centroid(burst,rate))<20,\
    (comparison.spectral_centroid(padded,rate),comparison.spectral_centroid(burst,rate))
assert abs(comparison.spectral_centroid(padded,rate)-3000)<200,"trailing silence must not erase the tone"
assert comparison.spectral_centroid([0.0]*5000,rate)==0.0,"a silent capture has no centroid"
# A lone transient above the threshold must not erase a quiet tone after it: the
# window is centred on that sample, so the two tails stay distinguishable.
def click_then_tone(frequency):
    samples=[0.0]*24000
    samples[0]=1.0
    for i in range(1,24000):
        samples[i]=0.02*math.sin(2*math.pi*frequency*i/rate)
    return samples
low=comparison.spectral_centroid(click_then_tone(3000),rate)
high=comparison.spectral_centroid(click_then_tone(10000),rate)
assert low>0 and high>0,"a click followed by a quiet tone still has a centroid"
assert high-low>4000,(low,high)
print("PASS: the centroid covers the full band and decay waits for a settled tail")

# A swapped stereo pair downmixes to the same mono signal; the per-channel metrics
# are what expose it, and the mono summary alone cannot.
rate=48000
left=[0.3*math.sin(i*0.01) for i in range(2048)]
right=[0.1*math.sin(i*0.02+0.3) for i in range(2048)]
swapped=comparison.describe(comparison.Audio(rate,[left,right]),comparison.Audio(rate,[right,left]))
assert swapped["correlation"]>0.99,"the mono downmix cannot see a channel swap"
assert swapped["channelMetrics"][0]["correlation"]<0.5 and swapped["channelMetrics"][1]["correlation"]<0.5,swapped["channelMetrics"]
# A candidate that outlasts the reference keeps its tail for decay and reports
# both capture lengths.
short=[0.0]*96+[0.3*math.exp(-i/200) for i in range(4096)]
longer=short+[0.2]*8000
report=comparison.describe(comparison.Audio(rate,[short]),comparison.Audio(rate,[longer]))
assert report["captureFrames"]["candidate"]>report["captureFrames"]["reference"]
assert report["referenceDecay60Seconds"] is not None
assert report["candidateDecay60Seconds"] is None,"a candidate that never settles must report no decay"
print("PASS: per-channel metrics expose a channel swap and a longer candidate keeps its tail")
