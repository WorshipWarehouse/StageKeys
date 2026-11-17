# Dynamic MIDI output spans

Issue #109 follow-up, started 3 November and verified 4 November 2026. This is an independent StageKeys display feature, not a complete performance-settings or reference-parity claim.

## Investigation and implementation plan

At baseline `53cbcf0`, keyboard range bands always used the authored input low/high values. Chord expansion, octave output, arpeggiator/sequence steps and transposition were not reflected. Implement an independent saved display choice; retain the previous static input-range default and avoid changing note routing, timing or audio rendering.

Settings → Performance → **Dynamic MIDI Output Ranges** switches the existing layer bands to the min/max span of currently gated MIDI output notes, after MIDI effects and layer/patch transposition. Chord gaps inside a span do not imply that every intervening pitch is played. Notes outside MIDI 0–127 are excluded before computing the span; the keyboard view clips to its existing 21–108 viewport. No active gate means no output band. The view polls at 20 Hz only in dynamic mode; this is visual feedback, not sample-accurate scheduling.

The scheduler maintains main-thread ownership by channel and emitted note key. Duplicate pitches remain visible until their last owned gate ends. Gate expiry, source release, program replacement and Panic use the same existing note-off callbacks, with display bookkeeping removed before notifying the consumer. Querying spans does not emit notes, advance the clock, or change the authored input range. Store suppresses dynamic output while stopped/loading or outside an isolated audition. The Tonic Pad has no module range band and is outside this display.

Sustain and audio/effect tails are deliberately outside the MIDI gate metric: releasing a note can remove its band while its sound continues. Muted/zero-gain modules may still emit MIDI according to the existing Disable Silenced Sounds policy. These are note spans, not audio meters or voice counters. All work is on the control/UI thread; no render callback or DSP change is introduced. Ownership storage follows currently emitted keys; no new preload/resource-budget claim is made.

An appended optional settings Boolean persists the choice through the existing recoverable writer; missing fields resolve to static ranges. Enabling during held notes uses already tracked gates, without replaying or stopping notes. Input highlights and on-screen keyboard playability remain independent. Range rows can shrink within their existing 85-point cap; accessible rows describe the sound and current MIDI span or inactivity.

## Verification scope

`DynamicMIDIRangeTests` runs in the existing library gate. Generated tests cover duplicate pitch/channel/source ownership, chord/octave/arp/sequence output, hold and deferred-release gates, source release, invalid transposition, query neutrality, mode switching during held notes, retained audio rendering, sustain semantics, Panic/Stop, persisted restart and legacy defaults. MIDIFXTests, MIDIInputTests and KeyboardPerformanceSettingsTests are adjacent checks.

Preload windows/eviction, measured native/AU budgets, optional per-sound audio meters, failure/external-storage matrices and prolonged physical stage qualification remain outstanding in #109. USB MIDI is the owner's requested controller connection; no physical keyboard boot/reconnect evidence is inferred from generated tests.

## Native Mac walkthrough — 4 November

The unsigned verified Mac app ran with an isolated generated-content data directory and master muted. A screenshot of the approximately 1194×866 window showed the active range band above the 88-key keyboard. Playing on-screen C4 produced MIDI 60 through 60; Panic cleared it. Settings exposed the saved dynamic toggle. Switching it off restored authored MIDI 0 through 127 ranges, and the off choice survived restart.

The first walkthrough exposed group labels overriding per-sound accessibility names. The final UI adds explicit child containment. After rebuilding, the accessibility tree separately reported Sound 1/2/3 with their generated fixture names and MIDI spans or “No active MIDI output.” Enabling dynamic mode, playing C4 and Panic were repeated successfully in the final build. This verifies Mac pointer/AX behavior at one window size, not spoken VoiceOver, all layouts, physical controller operation or mobile usability.

An observation requested after Quit caused the UI tool to relaunch against the normal app-data environment. That instance was closed without editing controls and is excluded from verification. No normal-session names, content or state are committed as evidence; the recorded walkthrough uses only the isolated generated fixture. The temporary test app is closed.

Local full suite: 110 reported passes, 11 explicit skips, no failures. The optional private-piano case remains unexercised despite reporting pass. Both final artifact gates passed. [Verification](Completion/dynamic-midi-ranges-verification.json) records exact commands, scopes, UI observations, logs and 220 final source/test/project/workflow hashes.
