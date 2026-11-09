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

## Sampler teardown ownership and verification (#192)

A hosted sampler that leaves the active graph is released through one
ownership registry and one disposal order. The registry keeps samplers weakly
plus their retained document state, so it can never keep a detached sampler
alive. Truncating the oldest tail (the documented hard two-tail bound) runs the
same order while the engine is stopped: mute, disconnect, detach, forget every
rack-side owner, then drop the references.

Truncation commits into the graph rollback instead of being undone. A released
tail cannot be restored, so the snapshot is pruned as a unit: its nodes, its
connection routes (including routes that pointed into a released node), its
captured voices, its tail records with their captured silence, its mixer and
effect entries and its branch records. A rollback after truncation therefore
restores a complete connected graph without that tail, never one that
references released nodes.

The transaction snapshot is moved out of its storage before completion and
filtered in place, so no second copy of the sampler list survives the restart.
Immediately before `engine.start()`, DEBUG builds check every sampler that the
transaction truncated or purged and record `releasedBeforeRestart` or
`retainedPastStop`. The bounded 64-entry ledger (`attached`, `retired`,
`truncated`, `purged`, `releasedBeforeRestart`, `retainedPastStop`) is exposed
as an optional field in the existing local support report; release builds record
nothing. No plug-in state, path, sample payload or session content is kept.

`Tests/ExternalGraphTailTests` drives both outcomes: truncation followed by a
rollback, and a forward restart failure whose rollback restart succeeds. It
asserts the evicted tail stays gone, the restored graph still renders, and no
truncated sampler is still alive at the stopped point. This is generated-tone
evidence on the offline graph; the owner's live macOS crash remains
unreproduced.

## Verification

`Tests/ExternalGraphTailTests.swift` uses generated tones and synthetic imported racks to exercise:

- an imported-rack topology change and a full instrument replacement;
- the replacement instrument's distinct 329.628 Hz generated voice at a matched synthetic dry-reference level while the retired 261.626 Hz instrument tail is still audible, with one active note intent;
- a held sustain release;
- stacked reverbs;
- explicit Panic clearing the retained tail;
- four rapid switches with a maximum of two retained tails and a bounded rack-node count after repeated same-size replacements;
- truncation followed by a rollback, and a forward restart failure whose rollback restart succeeds, with the sampler release ledger showing no truncated sampler alive at the stopped point before either restart.

`Tests/ReverbTransitionTests.swift` additionally checks the native effect path: compatible patch changes keep the tail, while `Silence Previous` and explicit Panic clear it.

The generated frequency measurement confirms that the new instrument signal is present over the old tail on the offline test graph; it is not a recorded acoustic test for clicks or real-instrument note doubling. The synthetic test does not establish perceptual equality, third-party AU behavior, or physical-device CPU/memory budgets. macOS/iOS builds, sanitizer runs, third-party AU lifecycle checks and a live listening test remain required. This document does not claim full Sunday Keys parity.
