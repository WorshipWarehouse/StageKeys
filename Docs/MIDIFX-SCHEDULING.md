# MIDI FX deadline scheduling

The arpeggiator and sequencer used a repeating 5 ms `Timer` that called
`advance(to:)` on a fixed grid. Every generated step, gate release and retrigger
was therefore quantized to the next 5 ms tick regardless of its musical
deadline. This record covers replacing that grid with one-shot timers armed at
the next deadline. It does **not** claim sample accuracy; the remaining
quantization is listed under [Limits](#limits).

## Change

`Sources/MIDIFXProcessor.swift` now exposes `nextDeadline`, the earliest pending
step, gate release or retrigger across all channels. `armTimer()` invalidates any
existing timer and arms a single-shot `Timer` for that deadline (immediately if
the deadline is already past). A timer that is already armed for an earlier or
equal deadline is kept. The scheduler re-arms after `advance(to:)`, tempo
changes, note-on/off, configure and panic, and clears the timer when no deadline
remains. `configure` no longer starts a polling timer for arpeggiator/sequencer
programs; the first deadline appears with the first note.

The processor's musical arithmetic is unchanged: `advance(to:)` still emits
every due step, applies gate releases and rescales the pending position on a
tempo change, so the existing timing and tempo-phase tests still apply.

## Measured dispatch quantization

`Tests/MIDIFXTimerTests.swift` drives the processor with an explicit clock, so
the measurement isolates the dispatch grid from OS timer latency and audio
render-block size. It plays eighth notes at 132 BPM for 59 s (260 steps) and
compares two ways of calling `advance(to:)`:

| Dispatch | Worst lateness | Mean lateness |
| --- | --- | --- |
| 5 ms polling grid | 5.000 ms | 2.432 ms |
| Armed at each deadline | 1 ns | 1 ns |

The 1 ns figure is the simulated delivery offset (a real timer fires at or just
after its deadline); the exact-deadline run has no grid quantization. The 5 ms
grid's worst case is one full tick, which is the defect this change removes.
The same test asserts that the armed deadline is the gate release when it
precedes the next step (0.2 s before 0.25 s at 120 BPM), that the next step is
due at 0.25 s, that the second release is 0.45 s, that a pending retrigger can
be the earliest deadline, and that releasing the last source clears every
deadline.

## Verification

Run in this Linux checkout with Swift 6.0.3 (`swiftc` from the official
ubuntu24.04 toolchain), compiling the Foundation-only scheduler sources and each
test directly (assertions enabled, no `-O`):

```
swiftc -DDEBUG Tests/MIDIFXTimerTests.swift Sources/MIDIFXProcessor.swift Sources/MIDIPrograms.swift -o /tmp/midifxtimer && /tmp/midifxtimer
swiftc -DDEBUG Tests/MIDIFXTests.swift Sources/MIDIFXProcessor.swift Sources/MIDIPrograms.swift -o /tmp/midifxtests && /tmp/midifxtests
swiftc -DDEBUG Tests/PatchTranspositionTests.swift Sources/MIDIFXProcessor.swift Sources/MIDIPrograms.swift -o /tmp/patchtrans && /tmp/patchtrans
```

All three pass. `MIDIFXTimerTests` is also in the default Swift list in
`Tests/test-library.sh`. The C library, sanitizer and distribution gates are
unaffected by this Swift-only change and were rerun (see the pull request).

`swiftc -O` disables Swift `assert`; an earlier local run with `-O` therefore
reported success without checking anything. The commands above use the same
assertion-enabled configuration as the macOS library gate.

## Limits

- Only the dispatch grid is measured. OS timer coalescing and main-run-loop
  latency on macOS were not measured here, and no macOS/Xcode build or Swift
  suite was run.
- Generated events still enter the synth at audio render-block boundaries, so
  the audible onset is quantized by up to one block (about 2.7 ms at 128 frames
  and 48 kHz, 10.7 ms at 512 frames). That quantization is unchanged by this
  work and is not sample-accurate.
- A truly sample-accurate arpeggiator/sequencer needs the step clock on the
  audio timeline, with generated events carrying sample offsets that the engine
  applies mid-block. This change does not add that path; it removes the 5 ms
  polling grid that sat in front of it.
- An already-armed earlier deadline is not rescheduled when a later deadline is
  added, which is correct for ordering but means a tempo change can leave one
  timer armed for a stale, earlier time; it fires, emits nothing that is not due,
  and re-arms. This is cheap but not a hard real-time guarantee.
- #111 and #10 remain open. This record covers only the MIDI FX dispatch part of
  #111's sample-accurate propagation criterion.
