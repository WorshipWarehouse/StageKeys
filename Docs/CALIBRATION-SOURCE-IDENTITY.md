# Calibration instrument and tempo context

3 November 2026. Issues #25 and #111 follow-up; broader instrument calibration and physical stage qualification remain open.

## Investigation and plan

At baseline `26f3362`, Output Level Match copied state directly from the rack channel whenever the draft named an Audio Unit. During an asynchronous replacement the rack can legitimately retain the previous instrument. Unlike save/editor capture, calibration did not use `AudioController.pluginStateData(channel:sound:)`, which verifies the requested sound against the accepted instrument. The isolated calibration could therefore receive another instrument's state instead of the draft's authored state.

Move calibration source capture behind one testable AudioController method and route the existing view through it. Reuse the existing installed-identity guard; do not add a second AU lookup or change graph/loading policy. Preserve every draft field, including exact authored state bytes when a matching AU is unavailable. Capture only the matching installed AU's live state. Leave the original draft, saved session, installed unit, held-note policy and live processing unchanged. Non-AU sources pass through unchanged.

The view also used the stored patch tempo rather than the resolved performed tempo. With tempo unlocked, calibration could clock synced processing at a different BPM from live playback, and changes to global live tempo did not invalidate the measurement. It now measures/watches `performedTempo`, displays the probe BPM, and retains that metadata when retargeting an existing result. Patch-lock versus live-tempo policy itself is unchanged.

## Reproduction and regression

The shared method was first exercised with the former view's unchecked capture logic. The generated AudioUnitCommitTests fixture failed with “Calibration must not borrow the previous instrument's state.” This is a production-host regression with generated instruments and state; it is not a third-party vendor compatibility claim or a physical UI walkthrough.

The expanded existing regression covers a native/sampler occupying the requested channel, a missing channel, pending and failed AU replacement, accepted AU live-state capture, unchanged non-state draft fields, unchanged caller-authored bytes, unchanged session bytes, and two AUs with the same display name but different component identities. Retained audio is rendered while replacement is pending. Existing rejected-state rollback, supersession, live engine/held-note and editor handoff checks remain in the same default gate. InstrumentGainMatchTests separately exercises actual isolated production rendering and the Apple DLS AU when available.

## Remaining acceptance

Issue #25 remains open for representative native/vendor AU qualification across playable/velocity splits, sustained and dense chords, evolving/tempo-dependent sounds, perceptual confidence, and the complete compare/reset/apply/undo/save-reload matrix. RMS/sample peak does not establish LUFS or true peak. This fix changes calibration state provenance and clock selection; it does not change the probe sequence, gain recommendation, trim application or DSP. Probe metadata/retarget checks exercise 72 and 137 BPM; PatchTranspositionTests and the virtual MIDI Store contract exercise locked versus live tempo. SwiftUI tempo invalidation is source-reviewed and compiled, not an automated interactive walkthrough. No reference application or proprietary assets were used.

Final local checks: four focused programs plus a separate virtual-MIDI Store tempo program passed; both universal Mac and generic Simulator artifact gates passed. Runner/inventory, accessibility source audit, distribution/content and whitespace checks passed. The local full default suite was not rerun; the complete hosted library gate remains required. [Verification](Completion/calibration-source-identity-verification.json) records commands, scopes, log hashes and all 219 frozen source/test/project/workflow inputs.
