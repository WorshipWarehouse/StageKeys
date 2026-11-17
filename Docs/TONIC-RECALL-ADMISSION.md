# Patch-locked Tonic Pad resource admission

Live patch selection, saved-setlist opening and JSON import now check a recalled Tonic Patch Lock sound alongside ordinary sound-layer resources, before note cleanup, current-state capture, document switching or persistence. The existing resource validator checks the managed preset and its sample references; the existing pad eligibility reader checks the supported looped-note or twelve-timbre selector map. This is read-only admission, not instrument instantiation or graph installation.

A bypassed saved pad is checked too: current recall configures its saved sound even when power is off. An unlocked patch with no saved pad state continues the existing live pad without validating or changing that independent choice. Stopped editing and startup/recovery behavior are unchanged. The saved velocity-selector flag is not migrated or rewritten by admission.

## Reproduction and verification — 4 November 2026

Baseline `7918e1d8c7af7507facd96c88e08a3ad37c51ad6`. Three isolated generated runs against its unchanged production core fail independently at “Missing recalled pad must not replace the active patch,” “Missing recalled pad must not replace the active setlist,” and “Missing recalled pad must not replace the imported performance.”

TonicRecallAdmissionTests uses a generated looped sampler pad and silent ordinary layers. It checks patch/setlist/JSON rejection, enabled and bypassed missing-preset recall, unsupported non-looping sampler maps, active document/snapshot identity, held notes/sustain/click, exact pad-unit identity and unchanged graph generation, unchanged model/session/settings/source bytes, and successful valid retry. Rendered output must remain finite and nonzero with ordinary layers and click silenced, so the retained pad alone supplies the energy. No private sound fixture is required.

Focused tests: TonicRecallAdmissionTests, TonicPadTests, SetlistResourceAdmissionTests, SetlistActivationTests and AudioStartupRecoveryTests. The complete native suite reports 114 passes, 11 explicit skips and no failures. Both unsigned artifact gates, seven runner self-tests, inventory/distribution and accessibility checks pass. Outcomes and 224 final input hashes are recorded in the accompanying verification JSON. Private-fixture skips and the absent optional piano case are not exercised private-content coverage.

## Remaining acceptance

Related #16, #123 and #114 remain open. Admission cannot guarantee later graph installation or prevent a file disappearing after validation. This does not provide an atomic asynchronous AU/graph transaction, repair saved sources, validate every later setlist patch, or change snapshot content semantics. Startup/recovery paths are not newly preflighted by this change. No physical MIDI/iPad, audible stage, latency, listening comparison, proprietary parity or prolonged soak qualification is claimed.
