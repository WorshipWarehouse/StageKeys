# Qualify live graph recovery on the stage rig

Tracks [#123](https://github.com/WorshipWarehouse/StageKeys/issues/123).
[NativeGraphRollbackTests](../Tests/NativeGraphRollbackTests.swift) injects
AVFAudio `-1` at the forward restart during a native sound replacement. It
checks that the original units and saved document survive, held and sustained
notes render after rollback, failed candidates do not accumulate tracked nodes
or tails, and the numeric cause reaches Support Diagnostics while the performer
gets retry guidance. This runs in the default library gate. It does not identify
the intermittent hardware trigger or measure uninterrupted audio. See
[graph completion recovery](GRAPH-COMPLETION-RECOVERY.md) for the separate
stopped-engine, pad, and click regression.

## Rehearsal procedure

1. Use an isolated test setlist and local recordings outside the repository.
   Record the tested commit/build, macOS version, AudioBox USB 96 output route,
   actual sample rate and buffer, and direct USB MIDI controller. Use a
   generated native sampler patch first. Set up a second sounding layer,
   Tonic Pad, and metronome so their behavior can be checked independently.
2. Hold a note, release a second note under sustain, and change one control
   at a time: replace a sound, edit an effect, then change a patch setting.
   Release pedal and keys after each attempt and check for stuck notes. Record
   the order and count of attempts. Test output and buffer changes separately
   so they are not mistaken for graph edits.
3. On failure, use **Settings → Audio → Copy Support Diagnostics** before
   attempting another change. Record the exact control and patch/layer index,
   previous and proposed values, output route, and timestamp alongside the
   report. Compare operation phase, graph generation, numeric domain and code,
   engine state, and graph restart/rollback details when present. A missing
   field is unknown; the audio route and user action are recorded separately.
4. Before retrying, note whether each layer, held note, pedal, pad and click
   still works; whether there was a click, unexpected silence, or a stuck
   note; and whether the UI and saved patch match the audible result. If
   audio stopped, check the on-screen recovery action and whether manual
   restart restores the saved patch, pad and click with fresh key input.
5. Repeat the edit sequence with a locally installed, authorized hosted AU.
   Record its version, attempt count and duration. For short local output
   captures, use **Record 30-Second Audio Check** in Audio Settings; label
   edit times and any audible interruption. Record graph node counts before
   and after batches using a diagnostic build or debugger. Process memory
   readings can supplement node counts; stable memory alone cannot prove
   graph nodes were released.

Keep private names, file paths, plugin state, samples, setlists, and recordings
out of GitHub. Publish only the reviewed diagnostics and a sanitized result
summary. If the real error does not occur, record the attempts as **not
reproduced**. A clean rehearsal and an injected failure are separate results;
the real trigger and repeated audible native/hosted AU recovery evidence remain
open.
