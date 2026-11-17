# Live previous-session recovery admission and clock

Recover Previous Session now validates the decoded/upgraded backup’s live first-patch sound and patch-locked pad resources inside the existing restore validation callback, before any damaged-primary copy or atomic primary replacement. If live resource admission rejects the candidate, the current performance and primary/previous bytes remain intact, no damaged archive is created and the recovery-required flag remains set. The backup can be repaired and retried. The restore helper’s byte bounds, schema/symlink/regular-file checks and damaged-file retention remain unchanged.

Successful running recovery applies the recovered patch, pad and performed audio clock. A locked recovered patch recalls its tempo without overwriting shared live tempo. The existing Panic policy clears held notes/pedal/click before successful activation; this change does not keep a click enabled automatically. Stopped recovery stays document-only and may restore a valid document even if its instrument resources are unavailable.

## Verification — 4 November 2026

Baseline `7a0b042429a4e2f9e1a2f6ec7035fc117c4024c6`. Two independent generated runs against its unchanged production core fail at “Unavailable recovery must retain the active performance and recovery flag” and “Recovered locked tempo must reach the rendered click clock.” The first establishes incorrect state/file publication for a known unavailable candidate; the second measures a stale rendered click despite a valid recovered document.

LiveSessionRecoveryTests uses isolated generated audio/documents. Missing layer and pad candidates must retain the active document/snapshot/unit identity/graph generation, held notes/sustain/click, finite nonzero instrument rendering (click disabled for measurement), primary and previous bytes and recovery flag, with zero new damaged archives. A valid retry restores exact backup bytes and retains the damaged primary in one archive; rendered click spacing at 48 kHz matches locked 150 BPM within eight frames while live tempo stays 90 BPM. Stopped document-only recovery accepts the unavailable resource document without starting an engine and preserves another damaged primary. Existing recovery, activation, pad and Store programs also run.

The complete native suite reports 115 passes, 11 explicit skips and no failures. Both unsigned artifact gates, seven runner self-tests, inventory/distribution and accessibility checks pass. Outcomes and 225 final input hashes are in the accompanying verification JSON. Explicit private-fixture skips and the absent optional private piano case do not establish private-content compatibility.

## Limits

Related #20, #16 and #111 remain open. This is first-patch admission and clock restoration, not complete migration/autosave/undo or clean-device portable recovery. A resource can disappear after admission; successful preflight cannot guarantee later graph or asynchronous AU installation. A successful on-disk restoration is not rolled back if a later graph install fails. Settings recovery keeps its existing restart-required policy. No physical MIDI/iPad, audible stage, latency, prolonged soak or reference parity qualification is claimed.
