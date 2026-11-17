# Saved Audio Unit availability and replacement

Implementation follow-up, 2 November 2026. This extends [Audio Unit recovery settings](PLUGIN-RECOVERY-SETTINGS.md) and [stopped-mode repair](RESOURCE-RECOVERY.md). It does not close the release milestone or establish cross-plugin/platform state compatibility.

## Behavior

Before attempting a new AU installation, the rack checks its component identity against the current device catalog. A missing component is rejected before instantiation or the plugin-loading journal's `begin`; absence alone therefore does not create a failed-load quarantine entry. Actual instantiation/state failures retain the existing recovery policy. Catalog presence is only a preparation check, not proof that loading or sound will succeed.

Resolution matches the component type/subtype/manufacturer triple. Saved display names and stale availability/validation metadata do not override a fresh installed match. On mobile, a currently listed third-party AUv2-only component is unavailable. If no match is present, saved Mac AUv2 metadata produces guidance to install a compatible iOS AUv3 version or choose a replacement. A fresh installed AUv3 match can supersede stale saved Mac metadata; that says nothing about whether the old serialized state is compatible.

Live selection of a patch with a known missing AU leaves the current performance intact. A failed Start retains the requested patch's identity, saved plugin state and snapshots. The preparation diagnostic says that an old sound remains available only when a live unit is actually present. While stopped, authored AU identity/state can still be edited or retained without installation or instantiation; type and document validation still apply.

The library checks saved AU entries against its current catalog snapshot. Missing/unavailable AU entries remain visible in All Sounds, My Sounds and ordinary custom collections, with an Unavailable label and reason; Add and Audition remain disabled while unavailable. Refresh Audio Units re-queries the catalog without rewriting the saved entry. The availability helper follows an authored layer's external identity before its legacy entry-level fallback, matching the library's selection behavior.

Audio Settings lists unavailable instruments in the selected patch by sound slot/name and reason, separately from failed-load blocks. Opening Settings, changing patch identity, refreshing availability, or granting retry permission updates this view. Blocked components are handled by the existing recovery list; allowing a block is not treated as installing a missing component. Stop audio to replace an unavailable sound, or install a compatible instrument, refresh and retry.

Missing instruments are never silently substituted or stripped of their state. An explicit replacement changes the layer/snapshot sound data by the existing edit contract. A user can explicitly save the unavailable layer to the sound library beforehand; state capture will not substitute another unit's state. No automatic backup/retargeting/conversion of vendor state is claimed.

## Evidence

`MissingAudioUnitTests` is added to the default gate. Pure fixtures cover missing-component reasons, triple-based matching despite changed names, stale metadata, Mac/mobile availability decisions and library rows becoming playable after a fresh catalog match without mutating the saved entry/state.

The store/rack checks use a DEBUG-only supplied catalog and generated instantiate hook. An explicit empty catalog must reject before that hook is called. They cover unchanged live selection/held pedal/unit/generation/session bytes, a direct rack rejection without a quarantine entry, unavailable slot rows, failed Start with retained plugin/snapshot bytes, explicit unavailable-preset library retention, stopped native replacement and rendered recovery. Rendering uses original generated WAV samples, stereo 48 kHz offline and 512-frame blocks.

Generated callback fixtures elsewhere may bypass real registry lookup when no supplied test catalog exists; this is DEBUG-only and not a production fallback or evidence of installed third-party components. The empty-catalog test takes precedence over that hook and proves the preparation boundary. No vendor plugin is installed, removed or executed for this test.

See [verification commands, results and frozen input hashes](Completion/missing-audio-units-verification.json). UI source compiles in Mac and Simulator artifacts; no interactive UI walkthrough or physical mobile/device-install qualification is inferred.

Final local verification: **109 program outcomes: 98 passed, 11 explicit private-fixture skips, zero failures**. One reported pass remains the known private PianoHeldNoteTests early return; it is not exercised piano evidence. Both unsigned release artifact gates passed, along with runner coverage/contract, distribution refusal/content, shell syntax and whitespace checks. All 204 frozen source/test/project hashes were unchanged after verification. C DSP sources were unchanged, so the earlier sanitizer result was not rerun.

The initial broad run caught missing-sample preparation guidance becoming generic when an empty slot had no retained unit. The unchanged SamplerStreamingStressTests was preserved, actionable guidance restored, and the complete final run passed.

## Limits

The catalog can change after preflight, and an installed instrument can still reject its state or fail to load. Registration, architecture availability and matching component triples do not prove identical versions, equivalent sound or portable state. Registry refresh latency, actual AU installation/removal, real vendor behavior, platform entitlements, physical mobile, hardware/storage/latency, prolonged rehearsal and the reported intermittent AVFAudio `-1` trigger remain unqualified. Unavailable entries outside the selected patch are inspected through the library or by selecting that patch while stopped.

No GitHub changes/closure, commit/push, signing, install or distribution were performed.

Subsequent work: [operation-scoped catalog observations](AU-CATALOG-OPERATIONS.md) deduplicates synchronous availability checks while retaining fresh observations for later operations and explicit UI refreshes. No wall-clock latency claim is inferred.
