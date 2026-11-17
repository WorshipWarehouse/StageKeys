# Tempo-synced delay continuity — #111

The native audio-effect delay (effect kind 3) reads from a tap whose distance is
derived from `clockTempo` and the subdivision in beats. Before this change a
tempo or subdivision change moved that read position in a single sample.

This record covers the native delay only. It is not a claim about Sunday Keys
timing, the imported stereo delay (which is set in seconds), the arpeggiator or
the sequencer.

## Measured defect

A 0.5-amplitude 997 Hz stereo tone runs through one delay slot with mix 100%,
zero feedback and a 20 kHz filter. The subdivision is one beat at 120 BPM, so the
tap starts 0.5 s behind. At 1.0 s the tempo changes to 240 BPM, which retimes the
tap to 0.25 s while both taps already carry tone. Blocks are 64 frames and the
same signal runs at 44.1, 48 and 96 kHz.

The number below is the largest sample-to-sample step, `max |y[n] - y[n-1]|`, in
steady state (0.60–0.98 s) and in the first three blocks after the change.

| Rate | Steady | Before change | Ratio | After change | Ratio |
| --- | --- | --- | --- | --- | --- |
| 44.1 kHz | 0.070866 | 0.674359 | 9.5× | 0.070839 | 1.00× |
| 48 kHz | 0.065114 | 0.493245 | 7.6× | 0.065347 | 1.00× |
| 96 kHz | 0.032566 | 0.369791 | 11.4× | 0.032727 | 1.00× |

Before the change the output steps by roughly the tone's peak-to-peak swing in
one sample. After it, the largest step is the tone's own slope.

## Change

`Sources/Synth.c` now keeps the previous and target tap distances per effect
slot. When the target moves by more than one sample, the old and new taps are
read together and crossfaded linearly over 20 ms
(`coef = 1 - exp(-1/(rate * 0.02))`). Both taps stay at a fixed distance during
the fade, so this is an overlap, not a pitch glide. A second change waits until
the current fade finishes, which keeps a continuously automated tempo retiming
in successive bounded overlaps instead of restarting every sample.

`clear_delay` resets the fade state, so Panic, an effect change and recovery snap
to the current time against a cleared buffer instead of fading from stale
history. The fade adds one extra tap read per sample for 20 ms after a change; it
allocates nothing and takes no locks.

The retime still changes the repeat's phase, as any new delay time must. What is
removed is the single-sample discontinuity.

## Regression

`Tests/DelayTempoTransitionTests.c` runs at 44.1, 48 and 96 kHz:

- a 997 Hz tone at 0.5 amplitude, one beat at 120 BPM, mix 100%, no feedback;
- tempo 120 → 240 at 1.0 s, then subdivision 1 → 2 beats at 1.3 s, so each
  change retimes between two taps that already carry tone;
- asserts the steady step is in 0.02–0.2, the peak exceeds 0.2, each change
  is at most twice the steady step plus 0.01, and every sample is finite and
  bounded;
- after Panic, sends one impulse and requires the wet peak at exactly one
  quarter second (11025, 12000 and 24000 samples), which proves the new time is
  reached rather than only smoothed;
- reports the measured steps:

```
PASS 44100 Hz: steady 0.0709, tempo 0.0709, subdivision 0.0709, settled 0.0709, impulse 11025/11025
PASS 48000 Hz: steady 0.0651, tempo 0.0653, subdivision 0.0651, settled 0.0651, impulse 12000/12000
PASS 96000 Hz: steady 0.0326, tempo 0.0327, subdivision 0.0326, settled 0.0326, impulse 24000/24000
```

The test is in the default native list in `Tests/test-library.sh` and in the
ASan/UBSan list in `Tests/test-reverb.sh`.

## Verification

Run on Ubuntu 24.04 with gcc 13.3.0. Apple CoreMIDI headers are unavailable, so
a local header shim supplied the MIDI event types; it is not committed.

- `DelayTempoTransitionTests` with `-O2`: PASS, values above.
- The same test with `-fsanitize=address,undefined`: PASS.
- Existing `AudioEffectsTests`, `DelayIndependentLevelsTests`, `ChannelDSPTests`,
  `ChannelPanicTests`, `RackTests`, `SynthTests`, `MetronomeTests` and
  `NativeSoundOrderTests`: PASS.
- `Tests/test-library-gate.py`: PASS (120 Swift, 9 C in the library gate, 22 in
  the sanitizer gate, 11 on demand).
- `Tests/test-local-library-runner.py`: 7 tests OK.
- `Tests/test-distribution.py` and `Tools/check-distribution.py --repo .`: PASS.

## Limits

- Only the native delay is covered. The arpeggiator and sequencer keep their
  main-thread MIDI FX scheduling; tempo reaches them by rescaling the next
  deadline, and dispatch arms one-shot timers at those deadlines instead of
  polling every 5 ms ([MIDIFX-SCHEDULING.md](MIDIFX-SCHEDULING.md)). This is
  still not sample-accurate UI scheduling.
- Tremolo is set in Hz, not in beats, so it has no tempo retime to smooth.
- The imported stereo delay is set in seconds and is unchanged.
- No listening comparison, macOS/Xcode build, Swift suite or hardware timing
  measurement was run. #111 and #10 remain open; this record covers only the
  delay-continuity part of #111's tempo propagation criterion.
