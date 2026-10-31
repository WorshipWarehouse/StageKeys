# Play In / Hear In and patch tempo lock — #111

Patch-level transposition and tempo are patch data. Play In is the key the
performer plays, Hear In is the key that sounds, and the difference plus an
optional octave shift is stored once in `Patch.transpose`, which remains the
single value used for playback.

## Key direction

A key change needs a direction, otherwise a two-semitone move and a ten-semitone
move are equally valid.

| Direction | Semitones from Play In to Hear In | Use |
| --- | --- | --- |
| `nearest` (default) | −5…+6 | Shortest move; a tritone resolves upward |
| `up` | 0…+11 | Keep moving upward |
| `down` | −11…0 | Keep moving downward |

`KeyDirection` is saved with the patch. A patch written without it resolves to
`nearest`, which is the interval older versions stored when both keys were set.

## Octave shift

`Patch.octaveShift` (−2…+2 octaves) is applied on top of the key distance, so the
sounding key can move by whole octaves without changing either key. The total is
clamped to ±24 semitones, the existing bound on `Patch.transpose`.

Patches saved before this field existed store only the total. `octaveShiftResolved`
derives the octave that explains that total instead of rewriting the document,
so an old setlist keeps its exact transposition and simply displays the octave
it was already using.

## Transposing programmed MIDI

Authored Easy Chord mappings and Sequencer steps store absolute MIDI output
notes. The patch transposition is applied as a single additive offset when notes
are emitted:

- the authored program is never rewritten, so repeated key changes cannot
  accumulate drift;
- `MIDIProgram` equality after any number of key changes is covered by
  `Tests/PatchTranspositionTests.swift`;
- output notes that would fall outside 0–127 are dropped rather than wrapped onto
  a neighbouring pitch.

## Tempo lock

`Patch.tempoLocked` defines which tempo a patch uses:

| Stored value | Behaviour |
| --- | --- |
| absent (`nil`) | Legacy: the patch stores and recalls its own tempo |
| `true` | Tempo lock on: the patch tempo is recalled with the patch |
| `false` | Tempo lock off: one live tempo is shared and survives patch switches |

The live tempo is persisted in `settings.json` (`SessionSettings.liveTempo`) and
restored at launch. Tap tempo, the stepper and direct BPM entry all write through
`PerformanceStore.updateTempo`, which updates the live tempo and the patch tempo
together so the toolbar always shows the tempo being played. Locking a patch
copies the current live tempo into that patch before it starts recalling it.

Tempo changes are queued to the audio engine (`sk_clock`) and re-apply
tempo-synced delay/effect values; the MIDI FX scheduler rescales the pending
musical position, which `PatchTranspositionTests` verifies across a 120 → 60 BPM
change. The scheduler runs on a 5 ms dispatch timer and the tempo reaches the
render graph through the engine's command queue, so this is musical phase
continuity, not a claim of sample-accurate scheduling from the UI.

## Verification

- `Tests/PatchTranspositionTests.swift` (hardware-free, in the default library
  gate) covers every Play In/Hear In pair for all three directions, octave
  wrapping and clamping, 200 repeated key changes without drift, authored
  mapping preservation, out-of-range drops, legacy octave derivation, tempo
  resolution and clamping, and arpeggiator phase across a tempo change.
- `Tests/ModelTests.swift` covers patch round-trip of the three new fields,
  legacy documents without them, and duplication.
- `Tests/test-library.sh` runs both through the existing harness.

Physical keyboard and hardware listening checks for the musical result remain a
separate release gate; nothing here claims a listening comparison.
