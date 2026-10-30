# Metronome

The metronome is a small, independent click engine (`SKMetronome` in
`Sources/Synth.c`). It does not share the synth's reverb, limiter or voice
state, and it has no audio-thread allocation, locking or file access.

This record describes StageKeys behavior. It is not a claim of sonic identity
with Sunday Keys click samples or patterns; the two sounds here are synthesized
independently.

## Controls

Settings → Metronome exposes, and `settings.json` persists, every control:

| Control | Range | Default | Behavior |
| --- | --- | --- | --- |
| Metronome | on/off | off | Enables the click. Turning it on starts a fresh bar immediately. |
| Show in toolbar | on/off | on | Hides or shows the toolbar metronome button. |
| Click sound | Click, Woodblock | Click | Two independently synthesized timbres. |
| Level | 0…100% | 60% | Scales the engine's bounded click peak; the UI shows the equivalent dBFS. |
| Beat velocity | 0…127 | 89 | Level of normal beats. |
| Downbeat accent | on/off | on | Uses the downbeat velocity for the first beat of the bar. |
| Downbeat velocity | 0…127 | 127 | Level of the accented downbeat. |
| Accent every | off, 1…16 beats | off | Accents every Nth beat after the downbeat at 1.25× the beat velocity, bounded to full scale. |
| Subdivision | Beats, Eighths, Triplets, Sixteenths | Beats | Adds softer clicks at 55% of the beat velocity. |
| Beats per bar | 1…16 | 4 | Moves the downbeat. The performance time signature is still displayed as 4/4. |
| Master volume controls the metronome | on/off | on | When off, the click keeps its own level as the master fader moves. |

Tempo remains the patch tempo (20…300 BPM), so Tap Tempo and the patch controls
update the click. Time signature, tempo and patch/snapshot identity are not
duplicated inside the metronome.

## Engine behavior

- The click is scheduled in samples, not by UI timers. It renders identically at
  44.1, 48 and 96 kHz and across arbitrary host block splits.
- A tempo or subdivision change scales the pending interval instead of
  restarting it, so the next click does not double-trigger or jump phase.
- Disabling the metronome truncates the click immediately. Panic silences the
  current click and schedules the next one a full interval later. Turning the
  metronome on starts a fresh bar immediately.
- Two presets are generated from a sine burst (Click) and a mixed sine/noise
  strike (Woodblock). To add a preset, extend `metro_sample` with another
  `preset` branch, add its display name to `MetronomeSettings.presets`, and add
  coverage in `Tests/MetronomeTests.c`. No recorded or vendor click samples are
  used.
- Saved values outside the ranges above make `SessionSettings.validate()` fail,
  which blocks automatic saves and surfaces recovery in Settings rather than
  silently clamping a hand-edited file. Missing metronome fields in older
  `settings.json` files resolve to the defaults above.

## Routing and levels

The click is rendered by a separate `AVAudioSourceNode` connected to the
protected output mixer, after the shared hall reverb and the master fader. It is
included in the output meter and the local 30-second audio check, and it passes
through the existing −1 dB output headroom. It is not sent through the shared
reverb.

The engine caps a click at 0.2 peak before output headroom. The level control
scales that peak, and 100% is not a measured sound-pressure level.

## Verification

`Tests/MetronomeTests.c` covers:

- click timing at 44.1/48/96 kHz with block sizes from 1 to 511 samples;
- tempo changes mid-beat, reset and immediate re-enable;
- downbeat, accent-every and beats-per-bar relationships;
- subdivisions and their lower level;
- both presets being finite, bounded and distinct;
- level, explicit stop and master-follow behavior;
- a 60-second 300 BPM run without drift.

`Tests/MetronomeSettingsTests.swift` covers defaults, JSON round trips, legacy
settings without the metronome block and rejection of out-of-range values.
`Tests/RackTests.c` retains a guard that the synth clock no longer renders a
click, which would double-trigger the app metronome.

Run them through the existing library harness:

```
python3 Tests/run-local-library.py . /tmp/stagekeys-library MetronomeSettingsTests
```

Native tests are linked by `Tests/test-library.sh`; `MetronomeTests` is part of
the default native list.

## Limits

- The performance time signature is fixed at 4/4. Beats per bar changes the
  accent pattern, not the displayed signature.
- There is no count-in and no external MIDI-clock sync.
- Multi-output and category routing are tracked by issue #107; until then the
  click shares the stereo system output without the hall reverb.
- Physical-device listening and latency remain part of the broader hardware
  gates and are not claimed here.
