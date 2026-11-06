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
| Count-in bars | 0…8 | 1 | Length of the one-shot **Count In** action. Zero hides the action. |
| Follow external MIDI clock | on/off | off | Uses MIDI Clock (24 PPQN) Start/Continue/Stop instead of starting the click directly. |

Tempo remains the patch tempo (20…300 BPM), so Tap Tempo and the patch controls
update the click. Time signature, tempo and patch/snapshot identity are not
duplicated inside the metronome. When external clock sync is active, the
derived clock tempo is shown and used by tempo-synced effects/MIDI FX for the
duration of the clock run. A tempo edit made during sync is stored as the
internal patch/live tempo for use after Stop; it does not replace the external
BPM while the clock owns the timing.

## Engine behavior

- The click is scheduled in samples, not by UI timers. It renders identically at
  44.1, 48 and 96 kHz and across arbitrary host block splits.
- A tempo or subdivision change scales the pending interval instead of
  restarting it, so the next click does not double-trigger or jump phase.
- Disabling the metronome truncates the click immediately. Panic silences the
  current click and schedules the next one a full interval later. Turning the
  metronome on starts a fresh bar immediately.
- **Count In** starts on a downbeat for the configured number of bars. If the
  click was off it stops after the last count-in bar. If the normal click was
  already on, Count In leaves its scheduler untouched, so there is no second
  start, early click or phase jump. Repeated count-in requests while the click
  setting is off restart as one-shot count-ins and still stop. Count-in uses the
  internal clock and is unavailable while external clock sync is on.
- **External MIDI clock** follows 24-pulse-per-quarter MIDI Clock. It ignores
  Song Position Pointer: Start resets to the first beat, Continue resumes on
  the next beat, and Stop silences the click without discarding the saved
  click setting. Tempo is smoothed from the 24-pulse interval and applied at a
  quarter-note boundary, so a change scales the pending interval rather than
  retriggering the current click. Ticks received while stopped are ignored for
  tempo, a discontinuous interval resets the measurement window, and losing the
  source that supplied the clock stops the click and restores the stored tempo.
  Only one configured source owns a run: Start or Continue selects it, and
  ticks or Stop from the other source are ignored until the owner stops or
  disconnects. The owner can restart the run with another Start.
- Clock ticks reserve queue capacity for Start/Continue/Stop, so a burst of
  pulses cannot make the render thread drop a later Stop when it is delayed.
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
- a one-shot count-in that stops after its bars, a repeated one-shot that still
  stops, and a count-in that preserves an already-running click's phase;
- count-in at 44.1/48/96 kHz with irregular block splits;
- external clock Start/Continue/Stop, 24 PPQN tempo derivation, a rejected
  discontinuous timestamp, and a transport slot that survives a tick burst;
- external clock at 44.1/48/96 kHz with irregular block splits;
- a 60-second 300 BPM run without drift.

`Tests/MetronomeSettingsTests.swift` covers defaults, count-in and clock
settings, JSON round trips, legacy settings without the metronome block and
rejection of out-of-range values. `Tests/MetronomeControlTests.swift` covers the Store
gate: a stopped engine or external clock sync never reaches the C scheduler,
an accepted count-in leaves the normal click setting alone, and the chosen bars
and clock opt-in survive `save()`. It also checks the pure MIDI Clock tempo
converter, including a reset and a gap that must not be smoothed into tempo.
The Store-level source-ownership and tempo-storage rules are not covered by the
C harness; they require the Swift/app test run on macOS.
`Tests/RackTests.c` retains a guard that the synth clock no longer renders a
click, which would double-trigger the app metronome.

Run them through the existing library harness:

```
python3 Tests/run-local-library.py . /tmp/stagekeys-library MetronomeSettingsTests
```

Native tests are linked by `Tests/test-library.sh`; `MetronomeTests` is part of
the default native list.

## Keyboard, accessibility and stopped audio

On macOS, **Shift-Command-M** toggles the click and **Shift-Command-I** starts
Count In. The toolbar buttons expose their state (On/Off) and Count In exposes
its bar count to assistive technologies; the level slider reports dBFS and the
velocity sliders report 0…127 values.

Count In follows the existing start policy. A stopped engine that still allows
automatic start is started before the count-in is scheduled. After a manual
**Stop**, or when audio startup fails, no count-in is scheduled and the UI asks
the performer to start audio or choose an available output; a specific startup
failure is not replaced by that message. Stopping, Panic, a graph failure or an
audio-device recovery resets the engine's count-in state, so a deferred click
cannot fire after a later start. Count In is unavailable while external MIDI
clock sync is on, because the external clock owns the timing. Turning external
clock sync on or off cancels a pending Count In, so a later normal click cannot
inherit its remaining bars.

## Limits

- The performance time signature is fixed at 4/4. Beats per bar changes the
  accent pattern, not the displayed signature.
- External sync is MIDI Clock only. Song Position Pointer, MIDI Time Code and
  transport recording are not implemented; Continue resumes on the next beat.
  Clock sync does not persist a new patch tempo and does not replace the
  patch/live tempo policy once it stops. Changing the tempo lock or tempo value
  during sync writes the stored internal tempo, not the clock BPM. After audio
  is stopped, restarted or recovered, the click waits for the next MIDI Start or
  Continue; it never free-runs against a clock that is not running.
- Multi-output and category routing are tracked by issue #107; until then the
  click shares the stereo system output without the hall reverb.
- Physical-device listening and latency remain part of the broader hardware
  gates and are not claimed here.
