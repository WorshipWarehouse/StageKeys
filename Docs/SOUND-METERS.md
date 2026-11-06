# Per-sound meters

StageKeys has an optional **Settings → Performance → Per-Sound Meters** view.
The setting is off by default and persisted in `settings.json`; older settings
files without the key load with meters off.

## Signal point

Each loaded external instrument channel is metered at a dedicated unity-gain
tap mixer, after that sound's instrument graph, three effect slots, channel
fader and pan. The tap mixer is downstream of the fader/pan mixer because
`AVAudioMixerNode` taps observe audio before that node's own `outputVolume` is
applied. The shared hall reverb, master fader and output limiter are downstream
and are not included. The tap mixer does not change gain, so moving the
per-sound fader changes the meter.

The Tonic Pad is metered when it uses an external instrument sound on its own
channel. Native synth layers and MIDI-output layers do not expose a per-sound
meter in this view. An empty slot has no active meter.

## What the reading means

The display is a **sample peak** over the most recent tap buffer, with the
matching RMS value available to tests and the settings panel. It is not a true
peak, LUFS, perceived loudness, or a measurement of the physical output. The
shared output meter in Audio Settings remains the post-limiter, final-mix
reading.

The tap callback only updates the existing lock-free `SKOutputMeter` counters.
It does not allocate, lock, read files, or edit the graph. When the setting is
off, StageKeys removes the taps; there is no per-sound callback overhead. The
first tap buffer after enabling can be silent while the graph produces its next
buffer.

Non-finite samples are excluded from peak/RMS, counted as `invalid`, and the
reading remains finite. A sample at or above full scale increments `overload`.
The meter bar turns orange for overload and red for invalid input. The numeric
reading is not clamped or gain-compensated.

## Verification

`Tests/SoundMeterTests.swift` uses a generated stereo source and the production
`SoundMeterBank` to verify:

- an enabled tap reports finite peak/RMS and zero invalid samples;
- halving the channel fader halves both readings;
- disabling removes the tap and no stale reading is exposed;
- re-enabling installs a fresh tap;
- the setting persists and defaults off for legacy settings.

The native macOS library runner executes the test with the rest of the default
suite. The test does not establish hardware meter accuracy, true-peak
compliance, loudness, or a visual/accessibility walkthrough.
