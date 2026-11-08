# #109 future qualification procedure

This is a plan for qualifying a future preload implementation. The feature and
its settings/status UI are not implemented by this documentation-only PR, so
these are not runnable steps or evidence of behavior today. The native memory
and CPU budget and real-rig behavior remain unverified. Nothing here is a
performance or reliability claim.

Record, for every run: build, machine, macOS version, audio interface, buffer
size, and the setlist used. Keep the numbers next to the run, not only in a
pass/fail line.

## 1. Memory and CPU budget (D-P4 byte ceiling)

1. Use authorized content and a setlist with an interior selected patch and
   enough eligible native-sampler neighbors to exercise the intended window.
   Record the number of eligible entries and their layer channels; do not use
   private samples as fixtures.
2. Select the target patch, disable preloading, and wait for the app to become
   idle with no warm entries. Record the app's **phys_footprint** in Activity
   Monitor or Instruments as the baseline for that patch.
3. Keep that same patch selected and set Previous 4 / Next 4 after the
   implementation exposes the controls. A full
   `Ready 8 of 8` requires eight eligible entries with non-colliding layer
   channels; otherwise record the actual window and ready counts rather than
   treating a smaller count as a failure.
4. Note phys_footprint again. Record the total resident delta and actual ready
   count. Require at least one successfully warmed entry to qualify the memory
   budget. If none warmed, record the delta and zero count, mark the measurement
   unrun, and leave the byte ceiling unset.
5. Capture process CPU use and render deadline misses over matched intervals
   with preloading off, during warming, and with the window resident. Keep the
   active patch and audio configuration constant and compare the measurements
   against limits agreed before marking this budget qualified.
6. Repeat with an AU-heavy setlist and confirm AU-only patches do not warm.
   Record the actual status denominator; do not assume it is eight.

The byte ceiling stays unset until memory and CPU measurements have been run
on at least two representative setlists. Do not put a figure in the code before
then.

## 2. Gap and cancellation

1. After implementation, set counts at 4/4 on a setlist that can cover eight
   eligible entries. Record whether the warm pass is audible and how long any
   gap lasts; do not assume the initial status is `Ready 0 of 8`.
2. Hold a key during selection and check that the status belongs to the current
   window. Its ready count may decrease when selection supersedes the old
   window. Confirm releasing the key allows the new warm pass to start.
3. Repeat with the sustain pedal down, then with a patch still loading.
4. Step Prev/Next faster than the 1.2 s settle delay, ten times, and confirm no
   stale entry is adopted and nothing stutters after the last selection.

## 3. Failure paths

1. With preloading off, keep patch A active and make a different patch B's
   sample unavailable (for example, move authorized test content to an
   unmounted external drive).
2. Enable a window that covers B without selecting B. Exercise the warm
   failure and verify A remains playable and the failure is surfaced as a
   preload failure. This distinguishes warm failure from activation preflight.
3. Reconnect the drive, retry warming, and confirm B can later be selected
   normally.
4. Repeat the warm-failure case with a corrupt or truncated generated sample.
   Test selecting an unavailable patch separately; it is not a substitute for
   exercising failure while a different patch remains active.

## 4. Real rig

- Physical keyboard and USB MIDI: notes, sustain, patch lock across selection.
- Touch/VoiceOver: focus order through the Performance settings section reaches
  the two steppers and the status line in a usable order.
- Restart: counts and the ready state restore correctly; a restart mid-pass does
  not leave a stuck `Preparing …` line.
- Prolonged performance: a full set with 4/4 counts, recording any dropout,
  memory growth or audible artefact.

## Reporting

Before qualifying activation latency, run the 20 cold and 20 warm activations
defined in [the design measurement procedure](PRELOAD-WINDOW.md#budgets-to-measure-before-choosing-numbers).
Report median and p95 from selection to the first rendered test note, using
matched patches and audio settings, including resource preflight time.

Put the recorded numbers and pass/fail per section in a comment on #109. If a
section cannot be run on available hardware, say so explicitly; an unrun section
is not a pass.
