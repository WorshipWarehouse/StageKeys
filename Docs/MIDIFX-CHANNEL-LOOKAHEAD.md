# Per-channel MIDI FX lookahead

`Docs/MIDIFX-LOOKAHEAD.md` added an opt-in horizon but left it disabled because
immediate consumers would receive notes early. This change applies the horizon
per channel: only channels whose hosted AU can accept a future sample time
advance through it. Every other channel stops at wall time, so external MIDI,
`AVAudioUnitSampler.startNote` and AUs without a schedule block keep deadline
dispatch and never receive a note early.

## Gating

- `MIDIFXProcessor.setLookaheadChannels(_:)` stores the channels allowed to
  advance through the horizon and re-arms the timer.
- `armTimer()` fires `lookahead` early only when at least one channel is marked.
- `advance(to:wall:)` computes a per-channel horizon: marked channels use the
  target, all others use `min(target, wall)`. Gate releases, skipped steps,
  retrigger deadlines, step times and velocity decay all use that horizon.
- `noteOn` timestamps direct events at the scheduler clock for a marked channel
  and at wall time for an unmarked one.
- `ExternalInstrumentRack.canSchedule(channel:)` requires a unit with
  `scheduleMIDIEventBlock` and no parallel imported branches.
  `AudioController.canScheduleMIDI(channel:)` additionally requires an external
  sound. `Store` recomputes the marked set through one helper,
  `refreshLookaheadChannels()`, once the rack has settled (see below).

## Refresh ordering

The marked set must describe the rack as it is *after* the change, not the
outgoing instrument. `refreshLookaheadChannels()` is the only computation, and
it runs:

- inside `configureMIDI`, which covers a committed layer and snapshot recall;
- from every `audio.configure` completion during patch activation, because that
  is where an asynchronous AU load assigns `externalSounds`;
- once the activation's pending set drains, which covers patch switch, layer
  move and layer reorder after all installs have reported.

## Verified

Linux, Swift 6.0.3, assertions enabled (`-DDEBUG`, no `-O`):

- `MIDIFXTimerTests.channelLookahead` — with a 10 ms horizon and only channel 0
  marked: dispatch at 0.24 s emits channel 0's 0.25 s step with a 0.25 s
  timestamp, while channel 1 still has only its note-on; dispatch at 0.25 s then
  emits channel 1's step at 0.25 s. `lookaheadEmission` also marks its channel.
- `MIDIFXTests`, `PatchTranspositionTests`, `MIDIAudioTimelineTests` and
  `MIDIDeliveryPolicyTests` still pass.

## Limits

- The refresh runs when an install *reports*. A rejected replacement keeps the
  outgoing unit resident, so the marked set can briefly describe the sound that
  is still playing, and a channel removed outside a configure call is not
  re-read. The next configure corrects both. Review this on macOS; none of it is
  exercised by the Linux tests.
- A marked channel's parallel branches can still be immediate, which is why
  `canSchedule` refuses channels with parallel branches.
- The AVFoundation calls remain unbuilt and unrun here; no macOS build, AU run,
  onset measurement or hardware timing test was performed.
- #111 and #10 remain open.
