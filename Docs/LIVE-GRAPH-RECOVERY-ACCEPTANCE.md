# Qualify live graph recovery on the stage rig

Tracks [#123](https://github.com/WorshipWarehouse/StageKeys/issues/123).
[NativeGraphRollbackTests](../Tests/NativeGraphRollbackTests.swift) injects
AVFAudio `-1` at the forward restart during a native sound replacement. It
checks that the original units and saved document survive, the held and sustained
notes each contribute their own fundamental after rollback, and tracked nodes
and tails stay bounded. The numeric cause reaches Support Diagnostics and the
performer gets retry guidance. This runs in the default library gate. It does not identify
the intermittent hardware trigger or measure uninterrupted audio. See
[graph completion recovery](GRAPH-COMPLETION-RECOVERY.md) for the separate
stopped-engine, pad, and click regression.

## Rehearsal procedure

1. Use an isolated test setlist and local recordings outside the repository.
   Record the tested commit/build, macOS version, AudioBox USB 96 output route,
   actual sample rate and buffer, and direct USB MIDI controller. Use a
   generated native sampler patch first. Set up a second sounding layer,
   Tonic Pad, and metronome so their behavior can be checked independently.
   For each native and hosted AU pass, use a continuously clocked independent
   recorder connected to the AudioBox line output. Record a matched no-edit
   control with the same notes, pad, click and levels. Label edit times and
   any audible clicks or gaps.
2. Before each edit, hold one key and release a second note under sustain.
   Change one control at a time: replace a sound, edit an effect, then change a patch setting.
   Keep the pedal and held key down until the note checks in step 4. Record
   the order and count of attempts. Test output and buffer changes separately
   so they are not mistaken for graph edits.
3. On failure, use **Settings → Audio → Copy Support Diagnostics** before
   attempting another change. Record the exact control and patch/layer index,
   previous and proposed values, output route, and timestamp alongside the
   report. Compare operation phase, graph generation, numeric domain and code,
   engine state, and graph restart/rollback details when present. A missing
   field is unknown; the audio route and user action are recorded separately.
4. After each edit, check each layer, both notes, the pad and the metronome
   while the held key and pedal are still down. Note any click or unexpected
   silence and compare the UI and saved patch with the audible result. Then
   release the pedal and keys and check for stuck notes. If audio stopped,
   follow the on-screen recovery action and check whether manual restart
   restores the saved patch, pad and click with fresh key input.
5. Repeat the edit sequence with a locally installed, authorized hosted AU.
   Record its version, attempt count and duration. Repeat the independent
   recording and matched control from step 1. **Record 30-Second Audio Check**
   in Audio Settings provides supplemental PCM from the engine tap. It appends
   only received frames, so stopped-engine time can be missing. Record graph
   node counts before and after batches using a diagnostic build or debugger.
   Use process memory readings as a supplemental measurement.

Keep private names, file paths, plugin state, samples, setlists, and recordings
out of GitHub. Publish only the reviewed diagnostics and a sanitized result
summary. If the real error does not occur, record the attempts as **not
reproduced**. A clean rehearsal and an injected failure are separate results;
the real trigger and repeated audible native/hosted AU recovery evidence remain
open.

## AudioBox rehearsal on 5 November 2026

On commit `8a2991c`, four scripted passes applied 144 total sound, effect and
tempo-lock edits at 48 kHz and 512 frames using generated native sounds and
Apple DLSMusicDevice 1.6.0. At cycle boundaries, tracked rack nodes rose from
24 to 32 after the first edit cycle and held at 32. One retired tail was
observed at most. The sentinel sampler retained note intent and the pad and
metronome stayed enabled at the checks. AVFAudio `-1` did not recur.

In the matched runs, the engine tap captured 9.600 seconds of PCM over
11.653 seconds (native) and 11.693 seconds (hosted). The no-edit control
captured 9.800 seconds over 9.895 seconds. The independent line-output
recording and real failure capture are still required.

## Patch-selection follow-up

The reported failure happened while playing the keyboard and selecting a patch
with the mouse. A follow-up on the same AudioBox route used the Store's patch
selection action with a generated CoreMIDI input. Before each selection, one
note was held and another was released under sustain. The three test patches
alternated between native samplers and Apple DLSMusicDevice.

All 36 selections settled with the expected patch, transposition and tempo.
The locked patches recalled 84 and 132 BPM. The unlocked patch kept the live
108 BPM. Note and pedal ownership was clear after release on every cycle.
The running graph had 24–40 tracked nodes and at most two retired tails at the
post-selection checks. No audio-change error was recorded. The maximum
selection-to-settled time was 88 ms, measured on the control path.

The probe was muted and used virtual MIDI. The intermittent error remains
unreproduced, and the control-path timing does not measure audible continuity.
