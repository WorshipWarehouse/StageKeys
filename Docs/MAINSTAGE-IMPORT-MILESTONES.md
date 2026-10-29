# Coordinated native MainStage release work

Tracks #6, #7, #8, #10, #85 and #87. These acceptance gates are related but are not all established by a shared importer or a green build.

## Import foundation

The new automatic entry point retains the original source, then searches the retained/selected source and known Mac sampler locations. Search results explain missing/unreadable locations. Different EXS bytes sharing a name stay ambiguous; equivalent copies may be attempted with their own sample roots. Discovery runs off the UI executor. Original source/sample files are never rewritten.

Each channel reports pending, prepared, converted, duplicate, needs-samples, unsupported, failed or cancelled status. The automatic UI flow explicitly permits supported-channel partial success; the existing strict conversion API remains all-or-nothing. A partial run is successful only for its reported committed subset, never represented as full patch conversion. Catalog writes remain one compare-before-commit transaction. Cancellation/commit failure removes newly prepared managed assets owned by that conversion; existing sounds/edits remain. Duplicate-aware retry is supported; persisted checkpoints and remembered folder bookmarks are still follow-up work.

Users can create a patch from ready channels in original order; omitted channels appear in conversion notes. Assembly now distinguishes channels with identical CST bytes by their verified metadata/channel identity. Import Sounds and the performance window accept dropped patches/channel strips. Whole concerts, folders of patches and multi-instrument channel topology remain explicit gaps; the app does not flatten these silently.

## Remaining coordinated milestones

- #6: source buses/sends/parallel channel relationships, additional controller curves/MIDI scripts and true multi-instrument topology; effects selection must preserve source order without silently exceeding visible slots.
- #7: versioned compatibility evidence and larger generated modern/legacy EXS behavior corpus; release/round-robin/crossfade and other unimplemented modes must stay explicit rejections.
- #8: persisted resumable work, cross-process transaction ownership and clean-host/relocation evidence beyond the generated baseline. Generated CI playback is evidence for that corpus only.
- #10: matched MainStage measurements for EQ/compressor transfer/transients and each delay/reverb/distortion response; control translation is not sonic parity.
- #85: remembered authorized folders, batch/whole-concert selection, supported multi-instrument decomposition and cold-user UI qualification.
- #87: personal portable writer/archive, document handling and precommit device eligibility; physical iPad round-trip/latency/memory is a separate required gate.

No vendor sample data is added to app/repository distributions. Generated `MainStageGuidedImportTests` builds original legacy/modern EXS, renders converted audio, checks original hashes, partial outcomes, same-CST identity, duplicate retry, strict/cancelled asset rollback and missing/ambiguous discovery. It reports whether MainStage is installed without launching it.
