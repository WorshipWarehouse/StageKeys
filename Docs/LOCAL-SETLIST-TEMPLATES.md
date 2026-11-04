# Local setlist templates and recovery safety

Any readable saved setlist can be used as a local blueprint with **Use as Template…**. The user supplies a trimmed 1–200 character name. The new saved setlist has independent document, patch, layer and snapshot identities, while sound references and other authored metadata are retained. It does not activate the copy or restart audio. Referenced sounds remain shared dependencies; their payloads are not duplicated or exported.

The browser offers Recently Updated (file modification time, not last-opened history) and Name A–Z, deterministic identity tie breaking, trimmed case-insensitive search and explicit empty states. Creation failures appear inside the browser. Existing duplicate and rename operations remain available.

A corrupt primary session previously left a fallback document with the saved active identity. Opening another setlist, creating a blank setlist or duplicating the active one could then overwrite the valid preserved library copy. `preserveCurrentSetlist` now rejects those operations while session/settings recovery is required, before capturing or writing the fallback. A different readable saved source may still be copied without activation. Recovery remains explicit in Settings; this change does not implement a general recovery-from-library workflow.

## Verification (2026-11-04)

The expanded SessionRecoveryTests failed against the unchanged main baseline with “Switching after a failed session load must not overwrite its preserved library copy.” All evidence used disposable generated documents. The initial baseline test compilation encountered a duplicate test variable; it was corrected before reproducing the runtime assertion.

`python3 Tests/run-local-library.py . /private/tmp/stagekeys-template-full` reported 111 passes, 11 explicit skips, no failures across 114 Swift and eight C programs. The optional private piano fixture was absent: its program reports PASS without exercising that fixture. No private fixture coverage is claimed. The seven local runner self-tests also pass.

SetlistTemplateTests checks independent identities and metadata, active/inactive sources, retained held notes/sustain/selection/snapshot/Patch Lock, nonzero offline generated audio, invalid names, missing source, library capacity, corrupt active-session preservation, and deterministic browser order/search. SessionRecoveryTests checks the preserved library bytes after blocked switching/new/duplicate operations, plus existing primary recovery cases.

Final unsigned universal macOS and generic iOS Simulator artifact gates pass, including distribution/content, document metadata and compiled icon checks. The local Simulator service reports a version mismatch; no Simulator runtime qualification is claimed. The accessibility static audit passes (45 sources, 11 pt floor). The final UI-only error/alert changes were rebuilt after the full core suite. Native UI walkthrough was attempted with isolated generated data and a muted master but blocked by the locked Mac; no visual/native interaction verification is claimed.

## Remaining scope

Related issues #114 and #20 remain open. This is a local template flow, not a curated template catalog, portable dependency package, share link, deep-link import, independent sound export, or clean-device roundtrip. MainStage translation and Sunday Keys parity are not established. Physical iPad operation and live stage qualification are separate acceptance gates.
