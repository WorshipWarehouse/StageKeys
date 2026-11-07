# Coordinated native MainStage release work

Tracks #6, #7, #8, #10, #85 and #87. These acceptance gates are related but are not all established by a shared importer or a green build.

## Import foundation

The new automatic entry point retains the original source, then searches the retained/selected source and known Mac sampler locations. Search results explain missing/unreadable locations. Different EXS bytes sharing a name stay ambiguous; equivalent copies may be attempted with their own sample roots. Discovery runs off the UI executor. Original source/sample files are never rewritten.

Each channel reports pending, prepared, converted, duplicate, needs-samples, unsupported, failed or cancelled status. The automatic UI flow explicitly permits supported-channel partial success; the existing strict conversion API remains all-or-nothing. A partial run is successful only for its reported committed subset, never represented as full patch conversion. Catalog writes remain one compare-before-commit transaction. Cancellation/commit failure removes newly prepared managed assets owned by that conversion; existing sounds/edits remain. Duplicate-aware retry is supported; persisted checkpoints and remembered folder bookmarks are still follow-up work.

Users can create a patch from ready channels in original order; omitted channels appear in conversion notes. Assembly now distinguishes channels with identical CST bytes by their verified metadata/channel identity. Import Sounds and the performance window accept dropped patches/channel strips, concerts and folders. A selection covering more than one source imports one source at a time, so an unreadable or unsupported source is reported instead of discarding the rest, and every source keeps its own retained archive. A channel that references several sampler instruments converts into one layer per instrument, in filename order, with the channel's gain split evenly across those layers; the source layers' relative balance stays archived but is not recovered. More than eight sampler references in one channel, or more than fifteen assembled layers, is an explicit refusal rather than a flatten.

## Batch and layered conversion (7 November 2026)

`MainStageBatch` enumerates a selection without opening it. A `.patch` folder or a `.cst` document selects itself; a `.concert` or any folder is searched up to eight folders deep for patch folders and channel strips, sorted by path, capped at 24 sources and 100,000 visited entries. Symlinks are skipped, and nothing in the selection is opened, converted or modified while enumerating.

`PerformanceStore.importMainStageBatch` converts those sources sequentially through the existing automatic path and reports `Batch import: N of M sources imported · C channels converted · D already installed · K need attention`, naming the sources it could not read. The last source's channel outcomes and searched locations stay on screen for review. Creating a patch from converted channels remains a separate, explicit action, so a concert import never replaces the current patch.

The status text for a decomposed channel lists each layer's own result, and its conversion notes state the gain split. A layer keeps the channel's processing, effects selection and MIDI program; only the channel fader is divided, so the converted channel's summed level stays at the source channel's level.

Verification: `MainStageBatchImportTests` selects a synthetic `.concert` containing two patch folders, a channel strip and a non-MainStage document, imports all three sources in one call, then converts a synthetic channel that references two EXS instruments and assembles it into ordered layers. It asserts the bounded selection, the per-source summary, each layer's recorded channel/instrument position, the equal split gain, the note and the refusal cases. Fixtures are generated; no MainStage document, vendor sample or user content is used, and MainStage is never launched.

Remaining in #85: a recorded cold clean-Mac run against a real MainStage library with no remembered folder, audible qualification of the imported layers, and recovery of the source layers' relative balance.

## Remaining coordinated milestones

- #6: source buses/sends/parallel channel relationships, additional controller curves/MIDI scripts and true multi-instrument topology; effects selection must preserve source order without silently exceeding visible slots.
- #7: versioned compatibility evidence and larger generated modern/legacy EXS behavior corpus; release/round-robin/crossfade and other unimplemented modes must stay explicit rejections.
- #8: persisted resumable work, cross-process transaction ownership and clean-host/relocation evidence beyond the generated baseline. Generated CI playback is evidence for that corpus only.
- #10: matched MainStage measurements for EQ/compressor transfer/transients and each delay/reverb/distortion response; control translation is not sonic parity.
- #85: remembered authorized folders, batch/whole-concert selection and supported multi-instrument decomposition are implemented and synthetically covered; cold-user clean-Mac UI qualification, audible review and relative layer balance remain open.
- #87: personal native writer/archive, document registration and ineligible-entry precommit refusal are implemented in the portable follow-up; physical iPad round-trip/latency/memory remains a separate required gate. See PERSONAL-SOUND-PACKS.md.

No vendor sample data is added to app/repository distributions. Generated `MainStageGuidedImportTests` builds original legacy/modern EXS, renders converted audio, checks original hashes, partial outcomes, same-CST identity, duplicate retry, strict/cancelled asset rollback and missing/ambiguous discovery. It reports whether MainStage is installed without launching it.
