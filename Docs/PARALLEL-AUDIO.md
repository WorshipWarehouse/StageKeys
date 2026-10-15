# Shared-input audio racks — v0.18

Audio-effect rack branches share one audio input and sum back together at the original point in the serial chain. They do not create extra sample voices or MIDI events. The saved branch speaker state, solo state, static selector range, output pan, mixer gain and nested serial/parallel effects are retained. Effect macros can target multiple branches and nested audio racks; compatible branch controls interpolate with snapshots.

The current ten-volume free library contains 26 parallel instrument patches and no multi-branch audio-effect racks. Audio fan-out is verified with synthetic saved racks and a deterministic audio source: both paths contribute, disabling one halves the signal, gain changes reach the render path, serial order is retained, and nested macro values survive persistence. Actual source audio-rack sound matching still needs an original Live comparison. Selector crossfade weights, selector automation, unsupported Live devices and MIDI rack fan-out remain incomplete.

Arpeggiators and sequencers now use anchored swung timelines, including inverse-swing step selection after a long scheduler stall. Free-rate schedules retain their deadline instead of drifting with each timer callback. The existing conventional swing model is not a Live groove-pool engine and is not sample accurate. Checked free presets store straight groove; absent global groove amounts remain explicit rather than guessed.

## Comparing library sounds

Select a library sound and press **Audition**, then play your keyboard. Other module audio and the Tonic Pad are temporarily silenced; the selected sound plays at a fixed audition level even if the destination module's saved fader is down. **Stop Audition**, **Cancel**, or closing the library restores the original mix. **Add Sound** commits the selected sound normally. Performance data is not rewritten by auditioning.

The reported Piano Patch contains SK App Felt Piano and Touchstone Piano, referencing different managed sample maps. Its saved Felt Piano fader was zero and Touchstone was at unity. An isolated production render confirmed distinct signals, but this does not establish that the pair is perceptually different enough or acoustically faithful to the original apps. Source filters, modulation and some sampler articulation remain approximations. The sound-identity test requires the user's private installed library; no samples are committed to GitHub.

Verification: Mac and iOS builds; deterministic audio fan-out/gain/persistence tests; instrument branch isolation and shared macros; groove/tempo/stall/sequence tests; library audition rollback; Store and MIDI plug-and-play regressions; all ten volumes and every parallel instrument patch through production playback.
