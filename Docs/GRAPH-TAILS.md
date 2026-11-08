# Reverb tails across graph replacement — #55

StageKeys keeps a replaced audio graph connected through a dedicated tail mixer so an existing reverb can decay instead of being cut off. The replacement becomes playable immediately; the retired graph receives no new MIDI or sample input.

## Covered replacements

- Replacing an imported instrument or Audio Unit rebuilds the channel voice. The old voice's mixer remains connected to the main mixer and is removed from the active channel map.
- Replacing an imported rack whose `audioTopology` changes keeps the old `ImportedAudioGraph` output alive through a tail mixer.
- Replacing parallel sample branches keeps the old branch mix alive through a tail mixer.
- A tail mixer feeds the channel's post-effect mixer, not the new graph's effect input. The new dry path therefore does not share an input bus with the retired graph.

## Bounds and controls

- At most two retired graphs are retained. A third retirement detaches the oldest tail during the graph transaction that is already stopping the engine.
- A retired graph's output is muted after 20 seconds. Silent graph nodes are detached during the next graph transaction; no engine stop is introduced solely to retire a tail.
- Retired samplers are excluded from the sampler-restoration list, so later patch transactions cannot reload them and delay the new instrument.
- `Silence Previous` and explicit Panic silence retired tails immediately. Normal patch changes preserve them when `Silence Previous` is off.
- Graph edits and retirement run on the main thread while the engine is already stopped. No node is attached, disconnected or rebuilt from a render callback.

## Verification

`Tests/ExternalGraphTailTests.swift` uses generated tones and synthetic imported racks to exercise:

- an imported-rack topology change and a full instrument replacement;
- the replacement instrument's distinct 329.628 Hz generated voice at a matched synthetic dry-reference level while the retired 261.626 Hz instrument tail is still audible, with one active note intent;
- a held sustain release;
- stacked reverbs;
- explicit Panic clearing the retained tail;
- four rapid switches with a maximum of two retained tails and a bounded rack-node count after repeated same-size replacements.

`Tests/ReverbTransitionTests.swift` additionally checks the native effect path: compatible patch changes keep the tail, while `Silence Previous` and explicit Panic clear it.

Sampler disposal ordering for replaced, evicted and purged voices is recorded in [SAMPLER-DISPOSAL.md](SAMPLER-DISPOSAL.md) (#192).

The generated frequency measurement confirms that the new instrument signal is present over the old tail on the offline test graph; it is not a recorded acoustic test for clicks or real-instrument note doubling. The synthetic test does not establish perceptual equality, third-party AU behavior, or physical-device CPU/memory budgets. macOS/iOS builds, sanitizer runs, third-party AU lifecycle checks and a live listening test remain required. This document does not claim full Sunday Keys parity.
