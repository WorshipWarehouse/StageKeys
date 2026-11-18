# PR integration and acceptance review — 17 November 2026

This integration starts at merged #229 (`a09f3af94d9fdb3a9a237356e3c31d1e5607d736`). It retains the following exact reviewed heads, resolving conflicts against the current main tree rather than dropping existing tests or repair/Undo controls.

| Original PR | Reviewed head | Disposition in this integration |
| --- | --- | --- |
| #230 | `537c2d6c79e9b55824cb05fee039dba8f6875a48` | Snapshot one-step Undo and AU ownership; compact captured identity avoids duplicating sampler maps/private metadata; document import/recovery invalidates outgoing Undo even when patch UUIDs match |
| #231 | `eef483219afdf9d09b824c9265b94a22c057805e` | Reject reserved MIDI learn before unlearning; preserve learn-release ordering and existing gates |
| #232 | `35090a782d4d2e2db211bf68fbf1d2d0798696ee` | Persist library order/random seed while retaining content repair/removal controls |
| #233 | `7996af74dca32e3a1490d4af1e65581a7929dc88` | One-shot restart fault proves graph remains running before retry; active Tonic ownership survives; remove click/pad energy before fresh-note proof |
| #234 | `aae5bb3fea4104471a4d9841c0677c9a84c55180` | Restore union of workflow gates, track/disconnect bend owner, reapply bend after replacement and preserve independent Tonic |
| #235 | `1796b3e1cf34a19a3725bff4ca33f20fc35af91a` | Assert shaping remains owned by sound edits across snapshot recall |

## Acceptance boundary

The six changes are scoped progress for #3/#15/#16/#17/#112/#123. They do not complete those entire issues. In particular, real Mac error reproduction and repeated native/hosted live changes remain required for #123; physical Mac route/latency and real-plugin work are not proved by generated fixtures.

Nord #212/#213 have a separate criterion-by-criterion proof in `NORD-NATIVE-VALIDATION.md`, original generated codec/mapping regressions and private local evidence from both owner-selected inputs. Decoder and mapping closure covers only the disclosed experimental attack-only subset, not full Nord sound behavior or intended-rig qualification. #214/#215 remain separate acceptance owners.

Physical iPad and iPhone acceptance is deferred to the owner's Later milestone, as recorded in `DEFERRED-IPAD-ACCEPTANCE.md`; no device result is marked passed. Simulator/shared-code gates remain required. No private sample, decoded audio, source session or plugin state is included in this integration.

The follow-up review also verifies saved sort direction/favorites navigation, invalidates Undo on sound-source replacement, preserves unrelated snapshot transitions, gates AU state preflight by component ownership, and bounds proof-tool reads before hashing. The pitch estimator uses original-rate samples and rejects out-of-range tones; private C4 measurements were repeated and the sanitized table updated.
