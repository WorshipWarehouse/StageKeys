# #109 qualification procedure

The software side of #109 is covered by the window, warm-voice and surface PRs.
Two acceptance items cannot be produced from a Linux CI runner: the measured
native/AU memory and CPU budget, and real-rig qualification. This procedure is
what turns them from "unverified" into evidence. Nothing here is a claim; it is
a script for the person at the instrument.

Record, for every run: build, machine, macOS version, audio interface, buffer
size, and the setlist used. Keep the numbers next to the run, not only in a
pass/fail line.

## 1. Memory and CPU budget (D-P4 byte ceiling)

1. Load the setlist with the largest real samples you use, start audio, and let
   the current patch settle with preload counts at 0/0.
2. Note the app's **phys_footprint** (Activity Monitor → Memory, or the memory
   graph in Instruments) as the idle baseline.
3. Set Previous 4 / Next 4 and wait for `Ready 8 of 8` on the Performance screen.
4. Note phys_footprint again. The difference is the resident cost of eight warm
   entries **for this setlist**; divide by the number of entries that actually
   warmed (patches without an external layer do not warm).
5. Play a normal patch change and watch CPU: the warm pass should be the only
   graph work, and moving between covered patches should not re-load samples.
6. Repeat with an AU-heavy setlist and confirm nothing warms for AU-only
   patches (`Ready 0 of n` is the expected reading).

The byte ceiling stays unset until step 4 has been run on at least two
representative setlists. Do not put a figure in the code before then.

## 2. Gap and cancellation

1. With counts at 4/4 and `Ready 0 of 8`, select a patch and listen for the warm
   pass. Record whether the gap is audible and how long it lasts.
2. Hold a key during selection and confirm the status line stays `Ready …`
   without a drop; release and confirm the pass starts.
3. Repeat with the sustain pedal down, then with a patch still loading.
4. Step Prev/Next faster than the 1.2 s settle delay, ten times, and confirm no
   stale entry is adopted and nothing stutters after the last selection.

## 3. Failure paths

1. Move one covered patch's sample folder to an external drive and unmount it.
2. Select that patch: the active patch must stay playable and the failure must
   be reported, not swapped in silently.
3. Reconnect the drive and confirm the patch loads normally.
4. Repeat with a corrupt or truncated sample file.

## 4. Real rig

- Physical keyboard and USB MIDI: notes, sustain, patch lock across selection.
- Touch/VoiceOver: focus order through the Performance settings section reaches
  the two steppers and the status line in a usable order.
- Restart: counts and the ready state restore correctly; a restart mid-pass does
  not leave a stuck `Preparing …` line.
- Prolonged performance: a full set with 4/4 counts, recording any dropout,
  memory growth or audible artefact.

## Reporting

Put the recorded numbers and pass/fail per section in a comment on #109. If a
section cannot be run on available hardware, say so explicitly; an unrun section
is not a pass.
