# Retired-tail silence across graph restoration

4 November 2026. Related to #55 and #123. This fixes host state restoration with generated evidence; real intermittent AVFAudio -1, vendor compatibility and physical stage qualification remain open.

## Investigation and plan

At baseline `b954301`, graph rollback restored the saved retired-tail silent flag and mixer gain. A tail silenced after the snapshot could be reactivated. Forward graph completion also restores mixer settings captured before an old voice became a retired tail; those gains could override its later Panic mute. A retired tail evicted by the two-tail cap can disappear before channel Panic and then return from a failed transaction's snapshot.

The expanded ExternalGraphTailTests reproduced the former rollback behavior with “Rollback must not revive a tail silenced after its snapshot.” This is a generated synchronous graph batch containing explicit rack Panic and an injected error, not a real performer-trigger or the reported intermittent AVFAudio -1 reproduction.

Retired-tail silence is terminal for that tail object. Preserve current/snapshot silent state and deadline expiry during rollback. Record fixed-size per-channel Panic generations separately from rollback state, so even an evicted tail restored from an older snapshot observes subsequent channel/global silence intent. Mixer restoration enforces zero gain for silent or expired retired tails before rendering resumes. Panic with preserved effect tails does not advance this silence generation. Active sampler note/controller rollback policy is unchanged.

All changes run on the existing main/control-thread graph path. No render callback, audio allocation, persistence format or tail-count/deadline setting changes. The two-tail cap explicitly truncates the oldest tail even if audible; it is not a measured CPU/memory ceiling. Silent nodes are still detached only at a later safe graph transaction. Reset/lost effect history is not reconstructed by rollback, and no phase-continuity or seamless-recovery claim is made.

## Verification scope

Generated sine fixtures form wet graph/instrument tails. The regression forces cap eviction before channel Panic and a failed edit, checks restored tail flag/gain and node bounds, preserves another channel's tail intent, and renders an unrelated held instrument after excluding other wet tails from the measurement. It also checks forward completion cannot restore a Panic-muted old mixer's gain, and confirms silence in the resulting output. Existing tail survival, stacked effects and preserved-tail Panic tests remain.

NativeGraphRollbackTests and GraphCompletionFailureTests are adjacent checks. Real piano/organ/pad articulation, vendor AU replacements, physical Silence Previous/Panic, audible clicks, latency, long rehearsal and measured hardware resource budgets remain required by the related issues.

Final local verification: three focused programs passed; the complete native suite reported 110 passes, 11 explicit skips and zero failures. The optional private-piano case remains unexercised despite reporting pass. Universal Mac and generic Simulator artifact gates passed. All 220 frozen source/test/project/workflow inputs matched afterward. [Verification](Completion/retired-tail-silence-verification.json) records exact commands, scopes and hashes.
