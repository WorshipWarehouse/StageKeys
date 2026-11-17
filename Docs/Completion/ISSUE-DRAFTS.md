# Proposed existing-issue descriptions

Local drafts for all 35 open issues. Preserve original history and acceptance; use these as appended enrichment pending review. Source facts are scoped to the audited commit. Test names below are execution plans unless EVIDENCE.md records them passing in this session. Full release/device/source qualification remains open even when a synthetic program passes.

## #2 — [P0] Prevent streaming clicks, loop errors and excess MIDI latency

Original: https://github.com/WorshipWarehouse/StageKeys/issues/2

### Problem Statement
Measure physical note-to-audio distributions and cold/slow-storage loading; preserve responsive cancel/recovery without partial playback.

### Current StageKeys Behavior
Region-boundary guards and pre-load residency exist; #80 repaired synthetic single-file gaps. #60 batched restoration.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Measure physical note-to-audio distributions and cold/slow-storage loading; preserve responsive cancel/recovery without partial playback. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: StageKeysSampler.swift, ExternalInstruments.swift, MIDIInput.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Measure physical note-to-audio distributions and cold/slow-storage loading; preserve responsive cancel/recovery without partial playback. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: StageKeysSampler.swift, ExternalInstruments.swift, MIDIInput.swift.
2. Reproduce the unmet behavior or record the missing qualification with: ImportedSampleContinuityTests, SamplerBoundaryRegressionTests, SamplerStreamingStressTests, SamplerStartupTests; repeat on representative zones and recorded hardware buffers.
3. Resolve prerequisites (110,123); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
110,123

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Measure physical note-to-audio distributions and cold/slow-storage loading; preserve responsive cancel/recovery without partial playback.
- [ ] Relevant regression/qualification completed: ImportedSampleContinuityTests, SamplerBoundaryRegressionTests, SamplerStreamingStressTests, SamplerStartupTests; repeat on representative zones and recorded hardware buffers.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
ImportedSampleContinuityTests, SamplerBoundaryRegressionTests, SamplerStreamingStressTests, SamplerStartupTests; repeat on representative zones and recorded hardware buffers. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P0; subsystem: sampler / latency. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #3 — [P0] Verify headroom, MIDI ownership and live audio recovery

Original: https://github.com/WorshipWarehouse/StageKeys/issues/3

### Problem Statement
Qualify combined headroom, repeated notes, supported pedal/bend/expression, device-change recovery; resolve N02 before headroom signoff.

### Current StageKeys Behavior
Post-output metering and synthetic source/channel ownership exist; click bypasses main limiter.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Qualify combined headroom, repeated notes, supported pedal/bend/expression, device-change recovery; resolve N02 before headroom signoff. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: AudioController.swift, Store.swift, MIDIInput.swift, ExternalMIDIOutput.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Qualify combined headroom, repeated notes, supported pedal/bend/expression, device-change recovery; resolve N02 before headroom signoff. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: AudioController.swift, Store.swift, MIDIInput.swift, ExternalMIDIOutput.swift.
2. Reproduce the unmet behavior or record the missing qualification with: OutputMeterTests, ChannelPanicTests, PlugAndPlayTests, ExternalMIDITests; physical disconnect/pedal/route and dense click-plus-layer capture.
3. Resolve prerequisites (110,123,N02); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
110,123,N02

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Qualify combined headroom, repeated notes, supported pedal/bend/expression, device-change recovery; resolve N02 before headroom signoff.
- [ ] Relevant regression/qualification completed: OutputMeterTests, ChannelPanicTests, PlugAndPlayTests, ExternalMIDITests; physical disconnect/pedal/route and dense click-plus-layer capture.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
OutputMeterTests, ChannelPanicTests, PlugAndPlayTests, ExternalMIDITests; physical disconnect/pedal/route and dense click-plus-layer capture. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P0; subsystem: audio / MIDI ownership. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #4 — [P0] Pass hardware performance soak and realtime resource budgets

Original: https://github.com/WorshipWarehouse/StageKeys/issues/4

### Problem Statement
Establish callback/render budgets and actual underrun instrumentation; run eight-hour supported-hardware soak after graph/recording work.

### Current StageKeys Behavior
C preallocation/queue and stress tests exist; diagnostics report underrunCount nil, not measured zero.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Establish callback/render budgets and actual underrun instrumentation; run eight-hour supported-hardware soak after graph/recording work. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: Synth.c, BuiltinEffectUnit.swift, AudioDiagnosticRecorder.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Establish callback/render budgets and actual underrun instrumentation; run eight-hour supported-hardware soak after graph/recording work. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: Synth.c, BuiltinEffectUnit.swift, AudioDiagnosticRecorder.swift.
2. Reproduce the unmet behavior or record the missing qualification with: EffectStressTests plus full ASan/UBSan suite; device script records p99/max render time, queue pressure, CPU/RSS, dropouts and stuck notes.
3. Resolve prerequisites (2,3,13,55,123,N01); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
2,3,13,55,123,N01

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Establish callback/render budgets and actual underrun instrumentation; run eight-hour supported-hardware soak after graph/recording work.
- [ ] Relevant regression/qualification completed: EffectStressTests plus full ASan/UBSan suite; device script records p99/max render time, queue pressure, CPU/RSS, dropouts and stuck notes.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
EffectStressTests plus full ASan/UBSan suite; device script records p99/max render time, queue pressure, CPU/RSS, dropouts and stuck notes. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P0; subsystem: real-time reliability. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #5 — [P0] Finish native MainStage import, preflight and missing-content repair

Original: https://github.com/WorshipWarehouse/StageKeys/issues/5

### Problem Statement
Complete declared-supported missing-content Locate/relink and cold-profile import outcomes. Batch concerts and multi-instrument work need retained ownership from closed #85.

### Current StageKeys Behavior
Native preflight, source hashes, bounded automatic discovery and remembered scoped folders are implemented.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Complete declared-supported missing-content Locate/relink and cold-profile import outcomes. Batch concerts and multi-instrument work need retained ownership from closed #85. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: MainStagePatch.swift, EXSNative.swift, Store.swift, SoundImportView.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Complete declared-supported missing-content Locate/relink and cold-profile import outcomes. Batch concerts and multi-instrument work need retained ownership from closed #85. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: MainStagePatch.swift, EXSNative.swift, Store.swift, SoundImportView.swift.
2. Reproduce the unmet behavior or record the missing qualification with: MainStagePreflightTests, MainStageGuidedImportTests, ReferencedMainStageImportTests; synthetic missing/ambiguous/moved originals and clean Mac without MainStage.
3. Resolve prerequisites (20; related 6,7,8,85); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
20; related 6,7,8,85

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Complete declared-supported missing-content Locate/relink and cold-profile import outcomes. Batch concerts and multi-instrument work need retained ownership from closed #85.
- [ ] Relevant regression/qualification completed: MainStagePreflightTests, MainStageGuidedImportTests, ReferencedMainStageImportTests; synthetic missing/ambiguous/moved originals and clean Mac without MainStage.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
MainStagePreflightTests, MainStageGuidedImportTests, ReferencedMainStageImportTests; synthetic missing/ambiguous/moved originals and clean Mac without MainStage. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P0; subsystem: MainStage import. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #6 — [P0] Translate MainStage channel routing, effects, macros and MIDI

Original: https://github.com/WorshipWarehouse/StageKeys/issues/6

### Problem Statement
Define supported topology before translation. Decode one authorized field at a time; preserve sends, bypass/order and supported macro/MIDI semantics or explicit omissions. Never execute source scripts.

### Current StageKeys Behavior
Faders and selected visible effects translate; #118 archives omitted macros/MIDI; sends and multi-instrument topology are reported.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Define supported topology before translation. Decode one authorized field at a time; preserve sends, bypass/order and supported macro/MIDI semantics or explicit omissions. Never execute source scripts. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: MainStageProcessing.swift, MainStagePatch.swift, ImportedAudioGraph.swift, Store.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Define supported topology before translation. Decode one authorized field at a time; preserve sends, bypass/order and supported macro/MIDI semantics or explicit omissions. Never execute source scripts. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: MainStageProcessing.swift, MainStagePatch.swift, ImportedAudioGraph.swift, Store.swift.
2. Reproduce the unmet behavior or record the missing qualification with: MainStageProcessingTests, MainStageLayerAssemblyTests, MainStageEffectSelectionTests, MainStageEffectSelectionImportTests; generated topology and source-hash fixtures plus matched renders.
3. Resolve prerequisites (5,7; coordinate 107,112); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
5,7; coordinate 107,112

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Define supported topology before translation. Decode one authorized field at a time; preserve sends, bypass/order and supported macro/MIDI semantics or explicit omissions. Never execute source scripts.
- [ ] Relevant regression/qualification completed: MainStageProcessingTests, MainStageLayerAssemblyTests, MainStageEffectSelectionTests, MainStageEffectSelectionImportTests; generated topology and source-hash fixtures plus matched renders.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
MainStageProcessingTests, MainStageLayerAssemblyTests, MainStageEffectSelectionTests, MainStageEffectSelectionImportTests; generated topology and source-hash fixtures plus matched renders. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P0; subsystem: MainStage topology / control translation. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #7 — [P0] Expand EXS compatibility and native instrument coverage

Original: https://github.com/WorshipWarehouse/StageKeys/issues/7

### Problem Statement
Qualify representative real-source modern/legacy selection/envelopes; implement only approved modes or preserve rejection. Unsupported synth engines can remain archive-only for a scoped release.

### Current StageKeys Behavior
Versioned support matrix and generated legacy/modern conversion/playback exist; unsupported modes remain rejected.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Qualify representative real-source modern/legacy selection/envelopes; implement only approved modes or preserve rejection. Unsupported synth engines can remain archive-only for a scoped release. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: EXSNative.swift, StageKeysSampler.swift, EXSCaptureCompatibility.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Qualify representative real-source modern/legacy selection/envelopes; implement only approved modes or preserve rejection. Unsupported synth engines can remain archive-only for a scoped release. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: EXSNative.swift, StageKeysSampler.swift, EXSCaptureCompatibility.swift.
2. Reproduce the unmet behavior or record the missing qualification with: ModernEXSImportTests, ModernEXSPlaybackTests, NativeSamplerGroupTests, EXSReferenceIdentityTests; corrupt and unsupported-mode fixtures and authorized matched source renders.
3. Resolve prerequisites (5; related 6,112); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
5; related 6,112

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Qualify representative real-source modern/legacy selection/envelopes; implement only approved modes or preserve rejection. Unsupported synth engines can remain archive-only for a scoped release.
- [ ] Relevant regression/qualification completed: ModernEXSImportTests, ModernEXSPlaybackTests, NativeSamplerGroupTests, EXSReferenceIdentityTests; corrupt and unsupported-mode fixtures and authorized matched source renders.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
ModernEXSImportTests, ModernEXSPlaybackTests, NativeSamplerGroupTests, EXSReferenceIdentityTests; corrupt and unsupported-mode fixtures and authorized matched source renders. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P0; subsystem: EXS / engine coverage. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #9 — [P1] Match Halo Shimmer musical behavior and parameter tapers

Original: https://github.com/WorshipWarehouse/StageKeys/issues/9

### Problem Statement
Measure matched pads/piano/held-note behavior, tapers and stability. Retain independent algorithm and disclose differences rather than tune to names.

### Current StageKeys Behavior
Independent pitch/alias/automation/tone/decay tests exist; no current matched Sunday audio observation.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Measure matched pads/piano/held-note behavior, tapers and stability. Retain independent algorithm and disclose differences rather than tune to names. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: Synth.c, ShimmerPitch.h, AudioEffectParameters.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Measure matched pads/piano/held-note behavior, tapers and stability. Retain independent algorithm and disclose differences rather than tune to names. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: Synth.c, ShimmerPitch.h, AudioEffectParameters.swift.
2. Reproduce the unmet behavior or record the missing qualification with: ShimmerPitch/Alias/Quality/Tail/ToneDecay/Automation tests at 44.1/48/96 kHz; matched reference render and blinded listening notes.
3. Resolve prerequisites (4 measurement protocol; related 11); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
4 measurement protocol; related 11

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Measure matched pads/piano/held-note behavior, tapers and stability. Retain independent algorithm and disclose differences rather than tune to names.
- [ ] Relevant regression/qualification completed: ShimmerPitch/Alias/Quality/Tail/ToneDecay/Automation tests at 44.1/48/96 kHz; matched reference render and blinded listening notes.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
ShimmerPitch/Alias/Quality/Tail/ToneDecay/Automation tests at 44.1/48/96 kHz; matched reference render and blinded listening notes. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1; subsystem: Shimmer DSP. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #10 — [P1] Match MainStage EQ, compressor, SilverVerb, delays and distortion

Original: https://github.com/WorshipWarehouse/StageKeys/issues/10

### Problem Statement
Measure transfer/transients, decay bands, wet/dry and order per supported processor; unsupported tape modes remain explicit.

### Current StageKeys Behavior
Independent EQ/comp/Silver/ClipDist/delays and clean Tape Delay subset implemented; precise ramp tests exist.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Measure transfer/transients, decay bands, wet/dry and order per supported processor; unsupported tape modes remain explicit. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: MainStageProcessing.swift, Synth.c, EQBandwidth.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Measure transfer/transients, decay bands, wet/dry and order per supported processor; unsupported tape modes remain explicit. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: MainStageProcessing.swift, Synth.c, EQBandwidth.swift.
2. Reproduce the unmet behavior or record the missing qualification with: EQBandwidthTests, ChannelCompressorTests, MainStageEffectAudioTests, MainStageTapeDelayTests, DelayIndependentLevelsTests; matched dry/isolated reference renders.
3. Resolve prerequisites (6 topology; related 7,112); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
6 topology; related 7,112

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Measure transfer/transients, decay bands, wet/dry and order per supported processor; unsupported tape modes remain explicit.
- [ ] Relevant regression/qualification completed: EQBandwidthTests, ChannelCompressorTests, MainStageEffectAudioTests, MainStageTapeDelayTests, DelayIndependentLevelsTests; matched dry/isolated reference renders.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
EQBandwidthTests, ChannelCompressorTests, MainStageEffectAudioTests, MainStageTapeDelayTests, DelayIndependentLevelsTests; matched dry/isolated reference renders. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1; subsystem: source processor DSP. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #11 — [P1] Complete native effect controls, presets and preview lifecycle

Original: https://github.com/WorshipWarehouse/StageKeys/issues/11

### Problem Statement
Inventory each meaningful control, bypass edit behavior and Confirm/Discard; separate audio UI and MIDI mapping follow-ups if approved, without hiding #16 snapshot contract decision.

### Current StageKeys Behavior
Three audio slots plus one MIDI slot and draft previews/presets exist; broad manual-derived MIDI constraints are only comments.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Inventory each meaningful control, bypass edit behavior and Confirm/Discard; separate audio UI and MIDI mapping follow-ups if approved, without hiding #16 snapshot contract decision. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: Editors.swift, AudioEffectParameters.swift, Store.swift, MIDIFXProcessor.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Inventory each meaningful control, bypass edit behavior and Confirm/Discard; separate audio UI and MIDI mapping follow-ups if approved, without hiding #16 snapshot contract decision. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: Editors.swift, AudioEffectParameters.swift, Store.swift, MIDIFXProcessor.swift.
2. Reproduce the unmet behavior or record the missing qualification with: EffectPresetTests, MIDIFXTests, GrooveTests, ReverbTransitionTests; UI preview/cancel/replace snapshot and sustained-note matrix.
3. Resolve prerequisites (16 contract; related 9,10,55); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
16 contract; related 9,10,55

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Inventory each meaningful control, bypass edit behavior and Confirm/Discard; separate audio UI and MIDI mapping follow-ups if approved, without hiding #16 snapshot contract decision.
- [ ] Relevant regression/qualification completed: EffectPresetTests, MIDIFXTests, GrooveTests, ReverbTransitionTests; UI preview/cancel/replace snapshot and sustained-note matrix.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
EffectPresetTests, MIDIFXTests, GrooveTests, ReverbTransitionTests; UI preview/cancel/replace snapshot and sustained-note matrix. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1; subsystem: effect editors / MIDI FX. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #12 — [P1] Finish Audio Unit discovery, editors and saved state

Original: https://github.com/WorshipWarehouse/StageKeys/issues/12

### Problem Statement
Publish real supported AU instrument state/duplicate/snapshot/tempo/route matrix and unavailable-plugin UX; #53 owns immediate editor presentation.

### Current StageKeys Behavior
Discovery/search, architecture availability, generic parameters and state foundation landed in #27/#94.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Publish real supported AU instrument state/duplicate/snapshot/tempo/route matrix and unavailable-plugin UX; #53 owns immediate editor presentation. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: ExternalInstruments.swift, PluginInterface.swift, PluginParameterModel.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Publish real supported AU instrument state/duplicate/snapshot/tempo/route matrix and unavailable-plugin UX; #53 owns immediate editor presentation. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: ExternalInstruments.swift, PluginInterface.swift, PluginParameterModel.swift.
2. Reproduce the unmet behavior or record the missing qualification with: AudioUnitCatalogTests, PluginParameterModelTests, AudioUnitTests with explicit installed component/version; stale callback and reopen/save/reload UI checks.
3. Resolve prerequisites (13; related 16,53); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
13; related 16,53

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Publish real supported AU instrument state/duplicate/snapshot/tempo/route matrix and unavailable-plugin UX; #53 owns immediate editor presentation.
- [ ] Relevant regression/qualification completed: AudioUnitCatalogTests, PluginParameterModelTests, AudioUnitTests with explicit installed component/version; stale callback and reopen/save/reload UI checks.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
AudioUnitCatalogTests, PluginParameterModelTests, AudioUnitTests with explicit installed component/version; stale callback and reopen/save/reload UI checks. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1; subsystem: AU discovery / state. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #13 — [P0] Isolate hosted plugin failures and validate audio/MIDI topology

Original: https://github.com/WorshipWarehouse/StageKeys/issues/13

### Problem Statement
Define supported containment contract. Main-thread state restore can prevent timeout; render faults/hangs/multi-output/latency are not isolated by the journal.

### Current StageKeys Behavior
Ten-second instantiate deadline, persisted pending-load blocking and AUv3 out-of-process request exist; AUv2 remains in-process.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Define supported containment contract. Main-thread state restore can prevent timeout; render faults/hangs/multi-output/latency are not isolated by the journal. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: ExternalInstruments.swift, PluginInterface.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Define supported containment contract. Main-thread state restore can prevent timeout; render faults/hangs/multi-output/latency are not isolated by the journal. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: ExternalInstruments.swift, PluginInterface.swift.
2. Reproduce the unmet behavior or record the missing qualification with: PluginRecoveryTests; controlled fault AU process/hang/state restore, next-launch recovery, mono/stereo/output and latency matrix; explicit in-process limitations.
3. Resolve prerequisites (123 graph contract; coordinate 107); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
123 graph contract; coordinate 107

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Define supported containment contract. Main-thread state restore can prevent timeout; render faults/hangs/multi-output/latency are not isolated by the journal.
- [ ] Relevant regression/qualification completed: PluginRecoveryTests; controlled fault AU process/hang/state restore, next-launch recovery, mono/stereo/output and latency matrix; explicit in-process limitations.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
PluginRecoveryTests; controlled fault AU process/hang/state restore, next-launch recovery, mono/stereo/output and latency matrix; explicit in-process limitations. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P0; subsystem: plugin containment / topology. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #14 — [P1] Complete physical iOS AUv3 support and define VST3 scope

Original: https://github.com/WorshipWarehouse/StageKeys/issues/14

### Problem Statement
Keep AU-only v1 policy unless owner changes it; qualify physical AUv3 editor/state/lifecycle and compatible-content availability. Do not add VST host by implication.

### Current StageKeys Behavior
Docs/PLUGIN-PLATFORMS explicitly defers VST3 and requires installed iOS AUv3; editor generation guards exist.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Keep AU-only v1 policy unless owner changes it; qualify physical AUv3 editor/state/lifecycle and compatible-content availability. Do not add VST host by implication. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: ExternalInstruments.swift, PluginInterface.swift, LibraryBackup.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Keep AU-only v1 policy unless owner changes it; qualify physical AUv3 editor/state/lifecycle and compatible-content availability. Do not add VST host by implication. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: ExternalInstruments.swift, PluginInterface.swift, LibraryBackup.swift.
2. Reproduce the unmet behavior or record the missing qualification with: PluginInterfaceRequestTests and availability tests; physical iPad/iPhone AUv3 load/rotate/split/background/route/state matrix.
3. Resolve prerequisites (12,13,113; physical gate 105); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
12,13,113; physical gate 105

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Keep AU-only v1 policy unless owner changes it; qualify physical AUv3 editor/state/lifecycle and compatible-content availability. Do not add VST host by implication.
- [ ] Relevant regression/qualification completed: PluginInterfaceRequestTests and availability tests; physical iPad/iPhone AUv3 load/rotate/split/background/route/state matrix.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
PluginInterfaceRequestTests and availability tests; physical iPad/iPhone AUv3 load/rotate/split/background/route/state matrix. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1; subsystem: mobile AU / plugin scope. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #15 — [P1] Finish external MIDI routing and controller setup

Original: https://github.com/WorshipWarehouse/StageKeys/issues/15

### Problem Statement
Verify Primary-only note policy vs Secondary learned controls, conflict/unlearn/reset scope, fixed CC defaults and real external reconnection.

### Current StageKeys Behavior
UID persistence, virtual routes, loop exclusion, learn and defaults exist; #111 now covers musical tempo/transpose. Confirmed source gaps: Store.handleMIDI dispatches both accepted controllers through the same notes/CC/PC switch; no pitch-bend case exists. MIDIControlTarget has no tonic brightness/shimmer or effect bypass/parameter targets. These do not satisfy the latest expanded acceptance in #15.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Verify Primary-only note policy vs Secondary learned controls, conflict/unlearn/reset scope, fixed CC defaults and real external reconnection. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: MIDIInput.swift, ExternalMIDIOutput.swift, MIDIControlTarget.swift, Store.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Verify Primary-only note policy vs Secondary learned controls, conflict/unlearn/reset scope, fixed CC defaults and real external reconnection. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: MIDIInput.swift, ExternalMIDIOutput.swift, MIDIControlTarget.swift, Store.swift.
2. Reproduce the unmet behavior or record the missing qualification with: MIDISetupTests, ExternalMIDITests, ManualMIDIDestinationRefreshTests, PlugAndPlayTests; two physical/virtual sources same pitch/channel and learned-control tests.
3. Resolve prerequisites (3; related 88,111,113); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
3; related 88,111,113

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Verify Primary-only note policy vs Secondary learned controls, conflict/unlearn/reset scope, fixed CC defaults and real external reconnection.
- [ ] Relevant regression/qualification completed: MIDISetupTests, ExternalMIDITests, ManualMIDIDestinationRefreshTests, PlugAndPlayTests; two physical/virtual sources same pitch/channel and learned-control tests.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
MIDISetupTests, ExternalMIDITests, ManualMIDIDestinationRefreshTests, PlugAndPlayTests; two physical/virtual sources same pitch/channel and learned-control tests. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1; subsystem: MIDI controls / external routes. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #16 — [P1] Verify all sound slots, patches, snapshots and Tonic Pad

Original: https://github.com/WorshipWarehouse/StageKeys/issues/16

### Problem Statement
Resolve D01 before behavior change. Preserve legacy snapshots, test patch-wide editing vs recall, notes/transitions/locks and tonic; AU pads remain disabled unless separately qualified.

### Current StageKeys Behavior
15-slot/five-slot models and sampler Tonic transactions exist; snapshot serialization stores broader parameters/AU state than latest manual-derived comment.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Resolve D01 before behavior change. Preserve legacy snapshots, test patch-wide editing vs recall, notes/transitions/locks and tonic; AU pads remain disabled unless separately qualified. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: Models.swift, SnapshotMorph.swift, Store.swift, PatchWorkflowViews.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Resolve D01 before behavior change. Preserve legacy snapshots, test patch-wide editing vs recall, notes/transitions/locks and tonic; AU pads remain disabled unless separately qualified. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: Models.swift, SnapshotMorph.swift, Store.swift, PatchWorkflowViews.swift.
2. Reproduce the unmet behavior or record the missing qualification with: AllSoundSlotsTests, SnapshotSlotTests, SnapshotMorphTests, TonicPadTests, ModelTests; sustained rapid recall and UI lifecycle on disposable sessions.
3. Resolve prerequisites (owner decision D01; related 55,111,112); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
owner decision D01; related 55,111,112

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Resolve D01 before behavior change. Preserve legacy snapshots, test patch-wide editing vs recall, notes/transitions/locks and tonic; AU pads remain disabled unless separately qualified.
- [ ] Relevant regression/qualification completed: AllSoundSlotsTests, SnapshotSlotTests, SnapshotMorphTests, TonicPadTests, ModelTests; sustained rapid recall and UI lifecycle on disposable sessions.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
AllSoundSlotsTests, SnapshotSlotTests, SnapshotMorphTests, TonicPadTests, ModelTests; sustained rapid recall and UI lifecycle on disposable sessions. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1; subsystem: patch / snapshots / tonic. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #17 — [P1] Finish library tags, sorting, filters and import workflows

Original: https://github.com/WorshipWarehouse/StageKeys/issues/17

### Problem Statement
Record actual layout/accessibility/empty/error/preview/cancel evidence. Distinguish persisted tag edits from uncommitted sound replacement.

### Current StageKeys Behavior
PR #119 implements destination labels, independent facets, filter chips, stable sorting and authored-tag provenance; #124 redesigns import.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Record actual layout/accessibility/empty/error/preview/cancel evidence. Distinguish persisted tag edits from uncommitted sound replacement. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: SoundBrowser.swift, LibraryBrowserModel.swift, SoundLibrary.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Record actual layout/accessibility/empty/error/preview/cancel evidence. Distinguish persisted tag edits from uncommitted sound replacement. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: SoundBrowser.swift, LibraryBrowserModel.swift, SoundLibrary.swift.
2. Reproduce the unmet behavior or record the missing qualification with: LibraryBrowserTests, LibraryNoteRangeTests, SoundRatingTests, MetadataRecoveryTests; real window-size keyboard/VoiceOver and cancellation checks.
3. Resolve prerequisites (19; related 5,20); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
19; related 5,20

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Record actual layout/accessibility/empty/error/preview/cancel evidence. Distinguish persisted tag edits from uncommitted sound replacement.
- [ ] Relevant regression/qualification completed: LibraryBrowserTests, LibraryNoteRangeTests, SoundRatingTests, MetadataRecoveryTests; real window-size keyboard/VoiceOver and cancellation checks.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
LibraryBrowserTests, LibraryNoteRangeTests, SoundRatingTests, MetadataRecoveryTests; real window-size keyboard/VoiceOver and cancellation checks. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1; subsystem: library UX / metadata. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #18 — [P1] Match modulation wheel and audit every reference page

Original: https://github.com/WorshipWarehouse/StageKeys/issues/18

### Problem Statement
Complete R01–R04 visible-page sequences/screenshots and window-size wheel tests; leave Demo-blocked/Prime behavior UNKNOWN.

### Current StageKeys Behavior
Wheel drag/hardware synchronization implemented; prior Demo audit and this matrix cover only bounded observations.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Complete R01–R04 visible-page sequences/screenshots and window-size wheel tests; leave Demo-blocked/Prime behavior UNKNOWN. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: PerformanceControls.swift, MIDIControlTarget.swift, Store.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Complete R01–R04 visible-page sequences/screenshots and window-size wheel tests; leave Demo-blocked/Prime behavior UNKNOWN. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: PerformanceControls.swift, MIDIControlTarget.swift, Store.swift.
2. Reproduce the unmet behavior or record the missing qualification with: ModulationWheelTests plus physical CC1 during drag/recall, accessibility adjustment and screenshots with version/license/date.
3. Resolve prerequisites (19; related 16,17); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
19; related 16,17

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Complete R01–R04 visible-page sequences/screenshots and window-size wheel tests; leave Demo-blocked/Prime behavior UNKNOWN.
- [ ] Relevant regression/qualification completed: ModulationWheelTests plus physical CC1 during drag/recall, accessibility adjustment and screenshots with version/license/date.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
ModulationWheelTests plus physical CC1 during drag/recall, accessibility adjustment and screenshots with version/license/date. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1; subsystem: reference matrix / wheel. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #19 — [P1] Finish responsive UI, accessibility and release visual identity

Original: https://github.com/WorshipWarehouse/StageKeys/issues/19

### Problem Statement
Audit keyboard focus, VoiceOver, contrast, scalable text/targets and every essential action across Mac/iPad/iPhone; define independent release identity.

### Current StageKeys Behavior
Wide/compact layouts, some accessible labels and flexible AU viewport exist; Mac minimum 1100×780 and fixed subpanels remain.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Audit keyboard focus, VoiceOver, contrast, scalable text/targets and every essential action across Mac/iPad/iPhone; define independent release identity. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: StageKeysApp.swift, Editors.swift, SettingsViews.swift, PerformanceControls.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Audit keyboard focus, VoiceOver, contrast, scalable text/targets and every essential action across Mac/iPad/iPhone; define independent release identity. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: StageKeysApp.swift, Editors.swift, SettingsViews.swift, PerformanceControls.swift.
2. Reproduce the unmet behavior or record the missing qualification with: Manual Mac resize/fullscreen/keyboard/VoiceOver and physical compact/orientation/split-view runs; screenshots and concrete failed controls.
3. Resolve prerequisites (product size/OS matrix; related 17,18); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
product size/OS matrix; related 17,18

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Audit keyboard focus, VoiceOver, contrast, scalable text/targets and every essential action across Mac/iPad/iPhone; define independent release identity.
- [ ] Relevant regression/qualification completed: Manual Mac resize/fullscreen/keyboard/VoiceOver and physical compact/orientation/split-view runs; screenshots and concrete failed controls.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
Manual Mac resize/fullscreen/keyboard/VoiceOver and physical compact/orientation/split-view runs; screenshots and concrete failed controls. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1; subsystem: responsive UI / accessibility. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #20 — [P0] Prove session migrations, atomic saves and portable recovery

Original: https://github.com/WorshipWarehouse/StageKeys/issues/20

### Problem Statement
Complete schema/migration/undo acceptance and interrupted multi-file save consistency; establish portable restore without silent defaults or data loss.

### Current StageKeys Behavior
Atomic per-file writes, previous-copy recovery and damaged ratings/preset/catalog protection implemented; session/settings are not one transaction.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Complete schema/migration/undo acceptance and interrupted multi-file save consistency; establish portable restore without silent defaults or data loss. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: SetlistLibrary.swift, SessionSettings.swift, Store.swift, LibraryBrowserModel.swift, Models.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Complete schema/migration/undo acceptance and interrupted multi-file save consistency; establish portable restore without silent defaults or data loss. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: SetlistLibrary.swift, SessionSettings.swift, Store.swift, LibraryBrowserModel.swift, Models.swift.
2. Reproduce the unmet behavior or record the missing qualification with: SessionRecoveryTests, MetadataRecoveryTests, CatalogRecoveryTests, StoreTests, SetlistLibraryTests; old/future/damaged/oversized/disk-failure and clean restore scenarios.
3. Resolve prerequisites (scope decision on multi-file contract; related 114,121); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
scope decision on multi-file contract; related 114,121

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Complete schema/migration/undo acceptance and interrupted multi-file save consistency; establish portable restore without silent defaults or data loss.
- [ ] Relevant regression/qualification completed: SessionRecoveryTests, MetadataRecoveryTests, CatalogRecoveryTests, StoreTests, SetlistLibraryTests; old/future/damaged/oversized/disk-failure and clean restore scenarios.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
SessionRecoveryTests, MetadataRecoveryTests, CatalogRecoveryTests, StoreTests, SetlistLibraryTests; old/future/damaged/oversized/disk-failure and clean restore scenarios. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P0; subsystem: persistence / recovery. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #21 — [P0] Complete release content provenance and signed distribution

Original: https://github.com/WorshipWarehouse/StageKeys/issues/21

### Problem Statement
Record owner licensing decision and provenance, then owner-authorized signing/notarization/clean install/update/rollback. Do not infer distribution qualification from CI.

### Current StageKeys Behavior
Source/bundle asset/notice gates and unsigned builds exist; no root LICENSE; #64 closed without decision in fetched discussion.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Record owner licensing decision and provenance, then owner-authorized signing/notarization/clean install/update/rollback. Do not infer distribution qualification from CI. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: Tools/check-distribution.py, Tools/verify-public-mac.sh, Resources, Licenses (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Record owner licensing decision and provenance, then owner-authorized signing/notarization/clean install/update/rollback. Do not infer distribution qualification from CI. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: Tools/check-distribution.py, Tools/verify-public-mac.sh, Resources, Licenses.
2. Reproduce the unmet behavior or record the missing qualification with: test-distribution.py, unsigned artifact gates; later read-only public signature/staple/Gatekeeper verification and clean-device install evidence.
3. Resolve prerequisites (4,20,23; owner license decision 64; applicable 105); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
4,20,23; owner license decision 64; applicable 105

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Record owner licensing decision and provenance, then owner-authorized signing/notarization/clean install/update/rollback. Do not infer distribution qualification from CI.
- [ ] Relevant regression/qualification completed: test-distribution.py, unsigned artifact gates; later read-only public signature/staple/Gatekeeper verification and clean-device install evidence.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
test-distribution.py, unsigned artifact gates; later read-only public signature/staple/Gatekeeper verification and clean-device install evidence. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P0; subsystem: distribution / provenance. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #23 — [P1] Finish diagnostics, onboarding, support and private beta

Original: https://github.com/WorshipWarehouse/StageKeys/issues/23

### Problem Statement
Finish actionable operation context #123, private support process, rehearsal beta exit criteria and measured diagnostics without private payload uploads.

### Current StageKeys Behavior
Local allowlisted diagnostics, audio checks and first-run guides exist; no measured underrun counter.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Finish actionable operation context #123, private support process, rehearsal beta exit criteria and measured diagnostics without private payload uploads. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: AudioDiagnosticRecorder.swift, Store.swift, SettingsViews.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Finish actionable operation context #123, private support process, rehearsal beta exit criteria and measured diagnostics without private payload uploads. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: AudioDiagnosticRecorder.swift, Store.swift, SettingsViews.swift.
2. Reproduce the unmet behavior or record the missing qualification with: SupportDiagnosticsTests, AudioDiagnosticRecorderTests; privacy review and representative musicians/rigs with explicit opt-in and recorded defects.
3. Resolve prerequisites (110,123,N01; beta depends 2,3,13,20); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
110,123,N01; beta depends 2,3,13,20

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Finish actionable operation context #123, private support process, rehearsal beta exit criteria and measured diagnostics without private payload uploads.
- [ ] Relevant regression/qualification completed: SupportDiagnosticsTests, AudioDiagnosticRecorderTests; privacy review and representative musicians/rigs with explicit opt-in and recorded defects.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
SupportDiagnosticsTests, AudioDiagnosticRecorderTests; privacy review and representative musicians/rigs with explicit opt-in and recorded defects. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1; subsystem: diagnostics / beta. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #24 — [Later] Build an independent StageKeys AI patch builder

Original: https://github.com/WorshipWarehouse/StageKeys/issues/24

### Problem Statement
Owner approves post-core scope, authorized-content resolver, preview/undo and remote opt-in. No proprietary service use, generated scripts, purchases or downloads.

### Current StageKeys Behavior
Validated local draft schema/tests exist, not a cloud generator or reference builder.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Owner approves post-core scope, authorized-content resolver, preview/undo and remote opt-in. No proprietary service use, generated scripts, purchases or downloads. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: Models.swift PatchDraftPlan; Docs/INDEPENDENT-PATCH-BUILDER.md (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Owner approves post-core scope, authorized-content resolver, preview/undo and remote opt-in. No proprietary service use, generated scripts, purchases or downloads. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: Models.swift PatchDraftPlan; Docs/INDEPENDENT-PATCH-BUILDER.md.
2. Reproduce the unmet behavior or record the missing qualification with: PatchDraftPlanTests with unknown IDs, out-of-range/nonfinite values and missing content; deterministic safe audition/cancel; usefulness evaluation only after approval.
3. Resolve prerequisites (core release qualification; owner product approval); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
core release qualification; owner product approval

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Owner approves post-core scope, authorized-content resolver, preview/undo and remote opt-in. No proprietary service use, generated scripts, purchases or downloads.
- [ ] Relevant regression/qualification completed: PatchDraftPlanTests with unknown IDs, out-of-range/nonfinite values and missing content; deterministic safe audition/cancel; usefulness evaluation only after approval.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
PatchDraftPlanTests with unknown IDs, out-of-range/nonfinite values and missing content; deterministic safe audition/cancel; usefulness evaluation only after approval. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
Later; subsystem: independent AI proposal. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #25 — [P1] Add user-controlled gain matching for native instruments and AUs

Original: https://github.com/WorshipWarehouse/StageKeys/issues/25

### Problem Statement
Qualify repeatability across instruments/articulations/ranges/tempo/AU readiness; describe RMS scope and sample-peak limitations, not universal perceived equality.

### Current StageKeys Behavior
Bounded fixed RMS/sample-peak trim, target/retarget and peak-vs-trim-limit reporting implemented.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Qualify repeatability across instruments/articulations/ranges/tempo/AU readiness; describe RMS scope and sample-peak limitations, not universal perceived equality. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: AudioDiagnosticRecorder.swift InstrumentGainMatch, SoundSettingsControls.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Qualify repeatability across instruments/articulations/ranges/tempo/AU readiness; describe RMS scope and sample-peak limitations, not universal perceived equality. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: AudioDiagnosticRecorder.swift InstrumentGainMatch, SoundSettingsControls.swift.
2. Reproduce the unmet behavior or record the missing qualification with: InstrumentGainMatchTests, PatchGainTests; quiet/invalid/nonrepeatable sources, headroom boost cap, apply/reset/undo and listening.
3. Resolve prerequisites (2,10,13); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
2,10,13

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Qualify repeatability across instruments/articulations/ranges/tempo/AU readiness; describe RMS scope and sample-peak limitations, not universal perceived equality.
- [ ] Relevant regression/qualification completed: InstrumentGainMatchTests, PatchGainTests; quiet/invalid/nonrepeatable sources, headroom boost cap, apply/reset/undo and listening.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
InstrumentGainMatchTests, PatchGainTests; quiet/invalid/nonrepeatable sources, headroom boost cap, apply/reset/undo and listening. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1; subsystem: gain calibration. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #53 — [P1] Open AU instrument editors immediately after adding a plugin

Original: https://github.com/WorshipWarehouse/StageKeys/issues/53

### Problem Statement
Record real custom/generic editor appearance, expand/scroll and dismissal on Mac; physical mobile evidence stays #14.

### Current StageKeys Behavior
One-shot add/dismiss/editor handoff and stale patch/layer/component checks landed through #94.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Record real custom/generic editor appearance, expand/scroll and dismissal on Mac; physical mobile evidence stays #14. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: StageKeysApp.swift, Store.swift, PluginInterface.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Record real custom/generic editor appearance, expand/scroll and dismissal on Mac; physical mobile evidence stays #14. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: StageKeysApp.swift, Store.swift, PluginInterface.swift.
2. Reproduce the unmet behavior or record the missing qualification with: PluginInterfaceRequestTests, PluginParameterModelTests; real installed AUv2/AUv3 immediate-add UI, rapid replacement, timeout and save/reload.
3. Resolve prerequisites (12,13; related 14); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
12,13; related 14

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Record real custom/generic editor appearance, expand/scroll and dismissal on Mac; physical mobile evidence stays #14.
- [ ] Relevant regression/qualification completed: PluginInterfaceRequestTests, PluginParameterModelTests; real installed AUv2/AUv3 immediate-add UI, rapid replacement, timeout and save/reload.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
PluginInterfaceRequestTests, PluginParameterModelTests; real installed AUv2/AUv3 immediate-add UI, rapid replacement, timeout and save/reload. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1; subsystem: AU editor workflow. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #55 — [P1] Preserve reverb tails when switching instruments or effect graphs

Original: https://github.com/WorshipWarehouse/StageKeys/issues/55

### Problem Statement
Qualify actual sustained piano/organ/pad/AU switches, no doubled routing, live tail/CPU/memory bounds; coordinate rollback separately with #123.

### Current StageKeys Behavior
PR #120 retains max two retired graphs, mutes at 20 s and detaches later; synthetic replacement/Panic tests exist.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Qualify actual sustained piano/organ/pad/AU switches, no doubled routing, live tail/CPU/memory bounds; coordinate rollback separately with #123. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: ExternalInstruments.swift, AudioController.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Qualify actual sustained piano/organ/pad/AU switches, no doubled routing, live tail/CPU/memory bounds; coordinate rollback separately with #123. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: ExternalInstruments.swift, AudioController.swift.
2. Reproduce the unmet behavior or record the missing qualification with: ExternalGraphTailTests, ReverbTransitionTests; repeated switches with sustain, Silence Previous/Panic, real AU and physical resource traces.
3. Resolve prerequisites (123; related 4,13); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
123; related 4,13

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Qualify actual sustained piano/organ/pad/AU switches, no doubled routing, live tail/CPU/memory bounds; coordinate rollback separately with #123.
- [ ] Relevant regression/qualification completed: ExternalGraphTailTests, ReverbTransitionTests; repeated switches with sustain, Silence Previous/Panic, real AU and physical resource traces.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
ExternalGraphTailTests, ReverbTransitionTests; repeated switches with sustain, Silence Previous/Panic, real AU and physical resource traces. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1; subsystem: tail lifecycle. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #88 — Powering on the MIDI keyboard selects the first patch (implicit Program Change mapping)

Original: https://github.com/WorshipWarehouse/StageKeys/issues/88

### Problem Statement
Capture physical keyboard boot event/source/channel and verify no patch/snapshot/tempo mutation; retain explicit mapping and Patch Lock tests.

### Current StageKeys Behavior
Explicit-only runtime mapping and #127 raw 0–127 numbering/unclaimed default are implemented; physical power-on cause unconfirmed.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Capture physical keyboard boot event/source/channel and verify no patch/snapshot/tempo mutation; retain explicit mapping and Patch Lock tests. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: Models.swift ProgramChangeMapping, Store.handleMIDI, Editors.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Capture physical keyboard boot event/source/channel and verify no patch/snapshot/tempo mutation; retain explicit mapping and Patch Lock tests. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: Models.swift ProgramChangeMapping, Store.handleMIDI, Editors.swift.
2. Reproduce the unmet behavior or record the missing qualification with: ProgramChangeOptInTests and virtual CoreMIDI suite; real boot before/after monitor if old build safely available, otherwise explicitly omit pre-fix recreation.
3. Resolve prerequisites (15; related 3); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
15; related 3

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Capture physical keyboard boot event/source/channel and verify no patch/snapshot/tempo mutation; retain explicit mapping and Patch Lock tests.
- [ ] Relevant regression/qualification completed: ProgramChangeOptInTests and virtual CoreMIDI suite; real boot before/after monitor if old build safely available, otherwise explicitly omit pre-fix recreation.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
ProgramChangeOptInTests and virtual CoreMIDI suite; real boot before/after monitor if old build safely available, otherwise explicitly omit pre-fix recreation. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1; subsystem: Program Change hardware. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #105 — [Deferred] Qualify personal sound packs on a physical iPad

Original: https://github.com/WorshipWarehouse/StageKeys/issues/105

### Problem Statement
Keep deferment. When resumed, AirDrop/Files import/play/large-piano memory and Mac-vs-iPad measured comparison with integrity/cancel checks.

### Current StageKeys Behavior
Software pack #87 closed with explicit physical qualification transfer here; owner paused physical iPad work.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Keep deferment. When resumed, AirDrop/Files import/play/large-piano memory and Mac-vs-iPad measured comparison with integrity/cancel checks. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: LibraryBackup.swift, mobile Info plist; Docs/PERSONAL-SOUND-PACKS.md (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Keep deferment. When resumed, AirDrop/Files import/play/large-piano memory and Mac-vs-iPad measured comparison with integrity/cancel checks. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: LibraryBackup.swift, mobile Info plist; Docs/PERSONAL-SOUND-PACKS.md.
2. Reproduce the unmet behavior or record the missing qualification with: PersonalSoundPackTests and LibraryBackupTests software baseline; actual iPad model/OS/pack/sample count/rate/buffer/startup/RSS/playback evidence.
3. Resolve prerequisites (owner resumes physical testing; 14,113 for full mobile release); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
owner resumes physical testing; 14,113 for full mobile release

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Keep deferment. When resumed, AirDrop/Files import/play/large-piano memory and Mac-vs-iPad measured comparison with integrity/cancel checks.
- [ ] Relevant regression/qualification completed: PersonalSoundPackTests and LibraryBackupTests software baseline; actual iPad model/OS/pack/sample count/rate/buffer/startup/RSS/playback evidence.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
PersonalSoundPackTests and LibraryBackupTests software baseline; actual iPad model/OS/pack/sample count/rate/buffer/startup/RSS/playback evidence. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
Deferred; subsystem: physical pack qualification. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #107 — [P1] Add device-aware category and per-sound Flex Routing

Original: https://github.com/WorshipWarehouse/StageKeys/issues/107

### Problem Statement
Define per-device pair/category/override persistence and unavailable-route fallback before building graph; account for click/tonic/tails.

### Current StageKeys Behavior
Only stereo system output is active; routingGroup alone does not route channels.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Define per-device pair/category/override persistence and unavailable-route fallback before building graph; account for click/tonic/tails. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: AudioDevices.swift, AudioController.swift, ChannelSettings.swift, SessionSettings.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Define per-device pair/category/override persistence and unavailable-route fallback before building graph; account for click/tonic/tails. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: AudioDevices.swift, AudioController.swift, ChannelSettings.swift, SessionSettings.swift.
2. Reproduce the unmet behavior or record the missing qualification with: Generated route policy/migration tests then multi-output hardware stereo/pan/FX/tail/route-change/missing-pair capture.
3. Resolve prerequisites (123,20; coordinate 13,112); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
123,20; coordinate 13,112

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Define per-device pair/category/override persistence and unavailable-route fallback before building graph; account for click/tonic/tails.
- [ ] Relevant regression/qualification completed: Generated route policy/migration tests then multi-output hardware stereo/pan/FX/tail/route-change/missing-pair capture.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
Generated route policy/migration tests then multi-output hardware stereo/pan/FX/tail/route-change/missing-pair capture. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1 scope gate; subsystem: multi-output routing. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #109 — [P1] Add bounded patch preloading, keyboard feedback and sound meters

Original: https://github.com/WorshipWarehouse/StageKeys/issues/109

### Problem Statement
Split preload lifecycle from keyboard/display/meter UX after approval. Establish actual memory/eviction budget; active graph survives cancelled/failed preload.

### Current StageKeys Behavior
Startup graph batching exists; no bounded previous/next preload manager or per-module meters.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Split preload lifecycle from keyboard/display/meter UX after approval. Establish actual memory/eviction budget; active graph survives cancelled/failed preload. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: Store.swift, ExternalInstruments.swift, PerformanceControls.swift, SessionSettings.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Split preload lifecycle from keyboard/display/meter UX after approval. Establish actual memory/eviction budget; active graph survives cancelled/failed preload. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: Store.swift, ExternalInstruments.swift, PerformanceControls.swift, SessionSettings.swift.
2. Reproduce the unmet behavior or record the missing qualification with: SamplerStartupTests and failure-injected preload tests; slow storage/large sounds/rapid Prev/Next/sustain; per-meter disabled-overhead benchmark.
3. Resolve prerequisites (123,13,55; routing contract 107 if included); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
123,13,55; routing contract 107 if included

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Split preload lifecycle from keyboard/display/meter UX after approval. Establish actual memory/eviction budget; active graph survives cancelled/failed preload.
- [ ] Relevant regression/qualification completed: SamplerStartupTests and failure-injected preload tests; slow storage/large sounds/rapid Prev/Next/sustain; per-meter disabled-overhead benchmark.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
SamplerStartupTests and failure-injected preload tests; slow storage/large sounds/rapid Prev/Next/sustain; per-meter disabled-overhead benchmark. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1; subsystem: preload / performance feedback. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #110 — [P0] Recover cleanly when the audio engine cannot start

Original: https://github.com/WorshipWarehouse/StageKeys/issues/110

### Problem Statement
Reproduce original AudioBox/competing-app failure; prove manual output selection/retry and unplug/sleep recovery become audible with session preserved.

### Current StageKeys Behavior
PR #117 implements six startup states/classification and three attempts with 0.25/0.75 s backoff; tests cover policy, not live failure.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Reproduce original AudioBox/competing-app failure; prove manual output selection/retry and unplug/sleep recovery become audible with session preserved. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: AudioController.swift startup types, Store.swift, StageKeysApp.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Reproduce original AudioBox/competing-app failure; prove manual output selection/retry and unplug/sleep recovery become audible with session preserved. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: AudioController.swift startup types, Store.swift, StageKeysApp.swift.
2. Reproduce the unmet behavior or record the missing qualification with: AudioStartupTests; real output contention/absence/mismatch and sleep/unplug trace, repeated starts must not duplicate engine/tap.
3. Resolve prerequisites (related 3,123); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
related 3,123

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Reproduce original AudioBox/competing-app failure; prove manual output selection/retry and unplug/sleep recovery become audible with session preserved.
- [ ] Relevant regression/qualification completed: AudioStartupTests; real output contention/absence/mismatch and sleep/unplug trace, repeated starts must not duplicate engine/tap.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
AudioStartupTests; real output contention/absence/mismatch and sleep/unplug trace, repeated starts must not duplicate engine/tap. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P0 validation; subsystem: startup recovery. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #111 — [P1] Implement musical Play In/Hear In transposition and patch tempo lock

Original: https://github.com/WorshipWarehouse/StageKeys/issues/111

### Problem Statement
Retain remaining sample-accurate timing/export/MainStage migration/live sustain acceptance. Decide bounded scheduling target; existing timer is not sample-accurate.

### Current StageKeys Behavior
PR #125 implements direction/octave/global-vs-locked tempo with deterministic all-key/mapping tests.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Retain remaining sample-accurate timing/export/MainStage migration/live sustain acceptance. Decide bounded scheduling target; existing timer is not sample-accurate. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: MIDIPrograms.swift, MIDIFXProcessor.swift, Store.swift, Editors.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Retain remaining sample-accurate timing/export/MainStage migration/live sustain acceptance. Decide bounded scheduling target; existing timer is not sample-accurate. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: MIDIPrograms.swift, MIDIFXProcessor.swift, Store.swift, Editors.swift.
2. Reproduce the unmet behavior or record the missing qualification with: PatchTranspositionTests, ModelTests, GrooveTests; tempo under UI load, export/reimport and held-note transitions with event timestamps.
3. Resolve prerequisites (16 contract; related 6,11); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
16 contract; related 6,11

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Retain remaining sample-accurate timing/export/MainStage migration/live sustain acceptance. Decide bounded scheduling target; existing timer is not sample-accurate.
- [ ] Relevant regression/qualification completed: PatchTranspositionTests, ModelTests, GrooveTests; tempo under UI load, export/reimport and held-note transitions with event timestamps.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
PatchTranspositionTests, ModelTests, GrooveTests; tempo under UI load, export/reimport and held-note transitions with event timestamps. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1; subsystem: musical keys / tempo. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #112 — [P1] Complete native ADSR, Mod Filter and sound signal ordering

Original: https://github.com/WorshipWarehouse/StageKeys/issues/112

### Problem Statement
Qualify imported sampler/AU order and supported source shaping; preview/revert under sustain; do not equate hidden native synth controls with user sampler envelope editing.

### Current StageKeys Behavior
PR #126 corrects native C order and exposes native ADSR/filter; imported AU chain differs; unsupported source shaping warned.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Qualify imported sampler/AU order and supported source shaping; preview/revert under sustain; do not equate hidden native synth controls with user sampler envelope editing. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: Synth.c, ChannelSettings.swift, AudioController.swift, ExternalInstruments.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Qualify imported sampler/AU order and supported source shaping; preview/revert under sustain; do not equate hidden native synth controls with user sampler envelope editing. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: Synth.c, ChannelSettings.swift, AudioController.swift, ExternalInstruments.swift.
2. Reproduce the unmet behavior or record the missing qualification with: NativeSoundOrderTests, ChannelSignalOrderTests, EXSEnvelopeTests; imported/AU signal-order render and sustained transactional edit/revert.
3. Resolve prerequisites (6,7; related 10,16); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
6,7; related 10,16

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Qualify imported sampler/AU order and supported source shaping; preview/revert under sustain; do not equate hidden native synth controls with user sampler envelope editing.
- [ ] Relevant regression/qualification completed: NativeSoundOrderTests, ChannelSignalOrderTests, EXSEnvelopeTests; imported/AU signal-order render and sustained transactional edit/revert.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
NativeSoundOrderTests, ChannelSignalOrderTests, EXSEnvelopeTests; imported/AU signal-order render and sustained transactional edit/revert. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1; subsystem: sound shaping / signal order. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #113 — [P1] Make iPad background audio and interruption recovery performance-safe

Original: https://github.com/WorshipWarehouse/StageKeys/issues/113

### Problem Statement
Define desired on/off background policy and begin/end/reset recovery states; preserve notes/sustain/tails/tempo where allowed without automatic surprise playback.

### Current StageKeys Behavior
iOS background audio mode exists, but non-active scene panics and every interruption notification stops audio; no persisted background policy found.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Define desired on/off background policy and begin/end/reset recovery states; preserve notes/sustain/tails/tempo where allowed without automatic surprise playback. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: StageKeysApp.swift, Store.swift, AudioController.swift, SessionSettings.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Define desired on/off background policy and begin/end/reset recovery states; preserve notes/sustain/tails/tempo where allowed without automatic surprise playback. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: StageKeysApp.swift, Store.swift, AudioController.swift, SessionSettings.swift.
2. Reproduce the unmet behavior or record the missing qualification with: Deterministic lifecycle policy tests, then physical screen lock/calls/Siri/route/media reset/thermal/MIDI tests; #105 deferment stays explicit.
3. Resolve prerequisites (110,123; physical owner gate 105); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
110,123; physical owner gate 105

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Define desired on/off background policy and begin/end/reset recovery states; preserve notes/sustain/tails/tempo where allowed without automatic surprise playback.
- [ ] Relevant regression/qualification completed: Deterministic lifecycle policy tests, then physical screen lock/calls/Siri/route/media reset/thermal/MIDI tests; #105 deferment stays explicit.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
Deterministic lifecycle policy tests, then physical screen lock/calls/Siri/route/media reset/thermal/MIDI tests; #105 deferment stays explicit. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1 mobile blocker; subsystem: mobile lifecycle. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #114 — [P1] Add portable setlist sharing, templates and independent library exports

Original: https://github.com/WorshipWarehouse/StageKeys/issues/114

### Problem Statement
Agree offline versioned metadata/dependency package and independent copies before links/templates; preserve IDs intentionally, no unauthorized assets.

### Current StageKeys Behavior
Local setlist CRUD/Trash and file documents exist; sound packs are not a setlist dependency package.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Agree offline versioned metadata/dependency package and independent copies before links/templates; preserve IDs intentionally, no unauthorized assets. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: SetlistLibrary.swift, Models.swift, PatchWorkflowViews.swift, LibraryBackup.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Agree offline versioned metadata/dependency package and independent copies before links/templates; preserve IDs intentionally, no unauthorized assets. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: SetlistLibrary.swift, Models.swift, PatchWorkflowViews.swift, LibraryBackup.swift.
2. Reproduce the unmet behavior or record the missing qualification with: SetlistLibraryTests, ModelTests and new generated package round-trips: collision/missing dependency/older schema/interruption/malformed paths; physical deferred.
3. Resolve prerequisites (20; product decision; related 17,21); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
20; product decision; related 17,21

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Agree offline versioned metadata/dependency package and independent copies before links/templates; preserve IDs intentionally, no unauthorized assets.
- [ ] Relevant regression/qualification completed: SetlistLibraryTests, ModelTests and new generated package round-trips: collision/missing dependency/older schema/interruption/malformed paths; physical deferred.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
SetlistLibraryTests, ModelTests and new generated package round-trips: collision/missing dependency/older schema/interruption/malformed paths; physical deferred. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P1 proposed scope; subsystem: portable setlists / templates. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #121 — [P1] Add opt-in CloudKit backups with transactional local recovery

Original: https://github.com/WorshipWarehouse/StageKeys/issues/121

### Problem Statement
Resolve D02. Define opt-in provider, eligible payload/consent and privacy/retention; reuse local transactional backup before network work.

### Current StageKeys Behavior
Existing issue proposes CloudKit but historical product docs exclude cloud; wording also calls Apple-managed CloudKit self-hosted.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Resolve D02. Define opt-in provider, eligible payload/consent and privacy/retention; reuse local transactional backup before network work. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: SessionSettings.swift, SetlistLibrary.swift, LibraryBackup.swift; no CloudKit source (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
The implementation/remaining-validation distinction above is code-supported. No new runtime root cause is asserted. Establish the exact failing phase or unmet behavior with the tests below before choosing a fix.

### Implementation Requirements
Resolve D02. Define opt-in provider, eligible payload/consent and privacy/retention; reuse local transactional backup before network work. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: SessionSettings.swift, SetlistLibrary.swift, LibraryBackup.swift; no CloudKit source.
2. Reproduce the unmet behavior or record the missing qualification with: After approval: offline account/quota/change/conflict, checksum/migration, interrupted upload/restore/rollback/deletion tests; no network implementation now.
3. Resolve prerequisites (20,114,21; explicit owner scope decision); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
20,114,21; explicit owner scope decision

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Resolve D02. Define opt-in provider, eligible payload/consent and privacy/retention; reuse local transactional backup before network work.
- [ ] Relevant regression/qualification completed: After approval: offline account/quota/change/conflict, checksum/migration, interrupted upload/restore/rollback/deletion tests; no network implementation now.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
After approval: offline account/quota/change/conflict, checksum/migration, interrupted upload/restore/rollback/deletion tests; no network implementation now. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
Later pending scope; subsystem: optional cloud backups. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.

## #123 — [P0] Recover atomically from intermittent AVFAudio error -1 during live changes

Original: https://github.com/WorshipWarehouse/StageKeys/issues/123

### Problem Statement
Add operation/generation/phase diagnostics and deterministic failing graph edit. Prove old graph and UI/session consistency through staged commit/rollback; choose mechanism from reproduction, not assumption.

### Current StageKeys Behavior
Error -1 is a user report; general graph edits mutate active state before finish and do not provide complete rollback. Exact trigger unknown.

### Expected Behavior
Satisfy the original issue’s retained acceptance criteria within the declared StageKeys release scope. Add operation/generation/phase diagnostics and deterministic failing graph edit. Prove old graph and UI/session consistency through staged commit/rollback; choose mechanism from reproduction, not assumption. Do not infer reference equivalence from control names or synthetic tests.

### Evidence
Current source: ExternalInstruments.swift editGraph/finishGraphChanges, AudioController.swift configure, Store.swift (under Sources unless a path is given). See 01-CURRENT-STATE-AUDIT, 02-REFERENCE-BEHAVIOR-MATRIX and EVIDENCE.md; original discussion and PR links remain authoritative historical context.

### Root Cause / Technical Assessment
Confirmed structural limitation: graph edits mutate connected state and finish with sampler/mixer restoration/restart, without a general prior-graph rollback. The actual intermittent AVFAudio -1 trigger remains unconfirmed.

### Implementation Requirements
Add operation/generation/phase diagnostics and deterministic failing graph edit. Prove old graph and UI/session consistency through staged commit/rollback; choose mechanism from reproduction, not assumption. Preserve existing source bytes, saved identities, supported platform behavior and working regressions. Keep related scope in its existing owner issue.

### Step-by-Step Implementation Plan
1. Re-read the current source and original discussion: ExternalInstruments.swift editGraph/finishGraphChanges, AudioController.swift configure, Store.swift.
2. Reproduce the unmet behavior or record the missing qualification with: Fault-injected graph edit before/after topology/sample load/restart; actual rendered continuity and note/sustain/tonic/metronome consistency; then real control/route reproduction.
3. Resolve prerequisites (110 existing states; coordinate 13,55; no new graph features first); write a bounded supported-behavior contract and a failing regression where a software defect is reproduced.
4. Implement only that approved delta, preserving formats and prior working behavior. If validation passes without a code change, attach evidence rather than rewrite working code.
5. Run the directly affected regression after the final edit, applicable platform builds, and the stated manual/device checks. Record unavailable checks separately.

### Dependencies
110 existing states; coordinate 13,55; no new graph features first

### Acceptance Criteria
- [ ] The original issue acceptance is retained and cross-referenced; each unmet item above has evidence or an explicitly approved deferral.
- [ ] Add operation/generation/phase diagnostics and deterministic failing graph edit. Prove old graph and UI/session consistency through staged commit/rollback; choose mechanism from reproduction, not assumption.
- [ ] Relevant regression/qualification completed: Fault-injected graph edit before/after topology/sample load/restart; actual rendered continuity and note/sustain/tonic/metronome consistency; then real control/route reproduction.
- [ ] Saved data/source hashes and unaffected playback/selection remain intact for the scenario.
- [ ] Platform, fixture, device and reference limitations are recorded; no skipped fixture is counted as a pass.

### Testing and Validation
Fault-injected graph edit before/after topology/sample load/restart; actual rendered continuity and note/sustain/tonic/metronome consistency; then real control/route reproduction. Use disposable generated content unless an explicitly authorized private fixture is required; keep private material outside version control.

### Definition of Done
A reviewer can reproduce the intended result at a recorded commit with the declared environment and inspect acceptance evidence. Existing regression coverage passes, unsupported scenarios are explicit, and every original criterion is completed or moved with owner-approved scope and a linked issue. Compilation alone is insufficient.

### Priority and Risk
P0 first implementation; subsystem: live graph atomic recovery. Live audio and data-loss risks outrank visual similarity. Complexity is relative and task-specific in 05-MASTER-ROADMAP.
