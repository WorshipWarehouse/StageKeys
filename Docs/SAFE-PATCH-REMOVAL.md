# Safe active-patch removal

Remove Patch previously deleted the active patch and released its notes before checking whether the resulting selection was playable. It also omitted the successor’s Tonic Patch Lock, performed clock and visual-mode recall. The UI disabled deletion during Patch Lock, but the Store action itself had no guard.

The Store now honors Patch Lock and the final-patch guard. Before live deletion it determines the same successor as the existing array policy (next patch, or predecessor when removing the last item) and checks its known layer/pad resources using existing activation admission. Rejection leaves the document, current units, held notes/pedal/click, pad, snapshot and saved bytes intact. Successful removal cancels audition/transition, follows the existing full-Panic policy, clears snapshot selection, recalls the successor’s visual mode/pad/performed tempo and saves. Explicit visual mode zero keeps the current view choice, matching ordinary patch selection.

Stopped removal is a document edit: invalidate instrument caches for next Start, without configuring/loading the successor or starting an engine. It remains possible to edit a document with unavailable sounds while stopped. Removing the final remaining patch remains a no-op.

## Verification — 4 November 2026

Baseline `2800c3bbf791b58842a6acc752b8ea28f1802265`. Three independent generated runs against the unchanged production core fail at “Unavailable successor must not delete the current patch,” “Deletion must recall the successor Tonic Pad,” and “Successor tempo must reach the rendered click after deletion.”

PatchRemovalTests uses isolated generated samples and a looped pad. It checks Store Patch Lock, missing successor layer/pad, exact document/unit/graph/snapshot/note/pedal/pad/click and session/settings byte retention, finite nonzero rendering with click silenced, successful middle removal, successor pad/visual state, actual 150 BPM click spacing at 48 kHz (eight-frame tolerance) with live tempo retained at 90 BPM, persisted restart, stopped last-position removal with an unavailable predecessor, no graph change/engine start, and final-patch guard. Focused programs include StoreTests, TonicRecallAdmissionTests, PatchReadinessTests and SetlistActivationTests.

The complete native suite reports 116 passes, 11 explicit skips and no failures. Both unsigned artifact gates, seven runner self-tests, inventory/distribution and accessibility checks pass. Outcomes and 226 final input hashes are recorded in the accompanying verification JSON. Explicit private-fixture skips and the absent optional private piano case do not establish private-content compatibility.

## Remaining acceptance

Related #16, #111 and #123 remain open. Admission cannot prevent a file disappearing afterward or guarantee later asynchronous AU/graph installation. A deletion is not rolled back for such a later install failure. This does not add patch Trash/undo or change snapshot content semantics. The existing successful-removal Panic policy can truncate effects/pad; seamless transition parity is not claimed. No physical MIDI/iPad, audible stage, latency, soak or proprietary parity qualification is claimed.
