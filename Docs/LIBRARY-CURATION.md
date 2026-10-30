# Library curation and imported processing (0.25)

Recommended is a curated flag: marked sounds first, alphabetical within each group. It is independent of ratings and insertion date. A sound's context menu can mark or unmark it. Unknown recommendation status is treated as unmarked, never guessed.

Imported free-preset display names drop trailing vendor labels, numeric vendor suffixes and the redundant Layered Patch label. IDs, sample paths and original names are retained. Inferred classification now recognizes guitars and plucks. Missing browsing Note Range tags receive suggestions from category (bass: left; leads: right; pads: full/mid; sequences: mid/right; other: full). These suggestions do not modify MIDI key splits. Explicit tags and explicit clears survive reloads. Inferred metadata is identified in the browser.

An optional personal `source-sound-tags.json` beside the user's library can supply authored metadata for exact-name, processed Sunday App entries. `Tools/catalog-tags.py` extracts only sound tags from an existing personal catalog export. Facets the export declares are copied; original templates win over saved copies; repeated tag names are listed once; and metadata the export does not declare stays unknown — an absent or empty facet is omitted rather than written as an authored empty clear, and a missing Source/Model is labelled `Not Tagged` instead of asserting a model. Values the app would refuse (an unrecognized Note Range or Complexity name) are dropped from that row and reported, so one unsupported value cannot discard a whole sound's metadata. Entries with unusable names are skipped and counted, an unexpected export shape is refused with a clear message, and the output is deterministic. Raw instrument imports are not relabeled as processed patches. Source catalogs and assets are not included in this repository or application. Invalid optional metadata is ignored. The legacy generated Felt Room entry receives authored tags once, preserving explicit range clears and recommendation overrides; future edits remain intact.

Direct channel imports previously loaded only the ExternalSound reference, discarding the saved library layer. They now use addLibrarySound so racks, nested processing, macro bindings, MIDI program, levels and bypass states survive. Existing free imports with missing racks continue to recover from matching library entries when selected. Existing customized nonnil racks remain unchanged.

The module's Rack FX link opens the existing sound settings rack editor. The library footer reports the processor count recursively, including bypassed processors. Imported effects remain in their original graph, separate from the three performance effect slots; they are not applied twice. Import reports no longer incorrectly claim that all effects and macros are discarded.

Remaining differences: inferred free-preset taxonomy is not authored Sunday metadata; source-native raw instruments still require reconstruction of their channel processing to match factory variants; unsupported Live processors and current DSP approximations remain documented per sound. Exact audible parity is not established by these metadata and routing fixes.

## Library workflow update (30 October 2026)

The library now distinguishes the two module outcomes in its header, primary button and accessibility labels: an empty module says **Add Sound**, a loaded module says **Replace Sound**. Cancel ends any audition and range preview before closing; it does not commit or discard the saved patch, and tag edits made through the context menu are already persisted. The same cleanup runs if the sheet is dismissed another way. A selection is committed only after the preview is ended, so a replacement cannot restore stale Audio Unit state.

Active filters appear as removable chips, including when the result list is empty, with a separate **Clear Filters** action. Each facet column scrolls independently and shows a no-values message when the other filters exclude every value; fixed Note Range choices and the Not Tagged choice remain available.

Re-selecting the current order keeps its chosen direction, and **Random** keeps its seed until another order is selected. Ties remain deterministic by name and then identity.

Tag provenance is recorded per facet for edits made after this version. `authoredFacets` marks explicit Note Range/Complexity edits and metadata loaded from the authored source-tag file; inferred name tags remain **Suggested**, and an absent optional facet remains **Not Tagged**. Legacy libraries without provenance keep their previous Suggested/unknown interpretation rather than being retroactively labelled authored. The footer shows the groups for the selected sound.

This update does not establish visual layout at real window sizes, physical Mac/iPad interaction, vendor-library compatibility, or audible/DSP parity. Those checks still require the relevant Mac or device qualification.
