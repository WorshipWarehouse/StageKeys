# Imported timing and nested racks — 0.16

The 213 free-library conversions now contain 488 translated effect instances, including 57 stereo delays, 213 effect macros and nine arpeggiator programs. No sample audio was resampled or modified.

## Added

- Simple Delay/CrossDelay: separate left/right beat divisions or millisecond times, timing offsets, linked time, feedback and dry/wet.
- Ping Pong Delay: cross-feedback stereo repeats, saved time, feedback, blend and an approximate band-pass filter. Processing is linear below the bounded safety clamp. Dedicated imported delay banks preallocate up to 16 seconds of delay memory before rendering. No allocation occurs in the render callback.
- Arpeggiator: supported up/down/up-down/down-up/as-played/chord/random styles, synced or free rate, gates up to 200%, hold, pattern offset, finite repeats, note retrigger, relative beat retrigger, chromatic transpose cycles and a linear velocity-decay approximation. MIDI disconnect tracks source ownership and forcibly clears latched notes even after their physical keys have been released; panic clears all generated notes. Repeated identical pitches close the previous generated instance before retriggering.
- Single-branch nested instrument, MIDI and audio racks are traversed in serial order. Nested macro scopes remain separate from the outer rack. Audio-effect rack branch gain is applied after its effects. Parallel branch effects/MIDI still require separate voices and are not flattened globally.
- Imported delay controls expose real left/right times, sync modes, ping-pong and filter bounds. The MIDI editor exposes the translated timing options and the full supported rate chooser.
- Library selection previews the selected sound's keyboard range without committing the sound. Cancel restores the original range. Replacing a facet column clears a hidden old filter; selecting an already-visible facet swaps columns.

## Fidelity limits

Historical numeric arpeggiator style/rate enums are inferred from saved chooser ordering, not verified by loading the source in Live. Delay time choices follow the historical Simple Delay buttons (1, 2, 3, 4, 5, 6, 8, 16 sixteenth notes). These mappings need an audible/visual source comparison before claiming parity.

Beat retrigger is aligned to the first incoming note, not Live's global song position. The MIDI scheduler runs on the main thread and is not sample accurate. Groove, scale-based transpose, additional arp styles, multi-device MIDI chains and branch-specific MIDI remain unsupported. Velocity decay is linear; its original curve may differ. Delay filters and time-change transitions differ; freeze is unsupported. Timing is capped at 16 seconds. EQ, compressor and reverb remain the approximations described in IMPORTED-BEHAVIOR.md. Instrument branch gain remains baked into sample zones, which can alter nonlinear processing response. Only translated macro targets are connected.

## Migration and preservation

The metadata upgrade compares existing racks with a saved 0.15 baseline and preserves customized racks. It keeps the previous rack metadata so matching legacy performance layers and snapshots can acquire new processing on activation. User performance FX, levels, names, ranges and MIDI choices are retained. A custom MIDI program is not replaced. Customized old rack snapshots remain intact.

## Verification

C impulse tests check independent stereo times, feedback amplitude, ping-pong routing, a three-second repeat and panic silence. A source-specific Hold test verifies unplug after key release and preservation of another input. Source fixture tests cover nested audio-rack order, beat/free delays, rates, overlapping gates, hold, forced release, finite repeats, velocity slope and JSON persistence. Production-graph checks render sounds from every volume, plus Under Over Arp and Noise Pluck Arp through the actual MIDI/sampler/stereo-effect/limiter path. GUI verification also exercised library search → Add Sound → imported arp controls (Chord, 1/8, 50% gate) and confirmed separate delay times of 1.00/0.75 beats. Source comparison with Live is still outstanding.

References: [Ableton MIDI effects](https://www.ableton.com/en/live-manual/11/live-midi-effect-reference/) and [Ableton audio effects](https://www.ableton.com/en/live-manual/11/live-audio-effect-reference/).
