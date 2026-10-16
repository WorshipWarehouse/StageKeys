# Library curation and imported processing (0.25)

Recommended is a curated flag: marked sounds first, alphabetical within each group. It is independent of ratings and insertion date. A sound's context menu can mark or unmark it. Unknown recommendation status is treated as unmarked, never guessed.

Imported free-preset display names drop trailing vendor labels, numeric vendor suffixes and the redundant Layered Patch label. IDs, sample paths and original names are retained. Inferred classification now recognizes guitars and plucks. Missing browsing Note Range tags receive suggestions from category (bass: left; leads: right; pads: full/mid; sequences: mid/right; other: full). These suggestions do not modify MIDI key splits. Explicit tags and explicit clears survive reloads. Inferred metadata is identified in the browser.

An optional personal `source-sound-tags.json` beside the user's library can supply authored metadata for exact-name, processed Sunday App entries. `Tools/catalog-tags.py` extracts only sound tags from an existing personal catalog export. Raw instrument imports are not relabeled as processed patches. Source catalogs and assets are not included in this repository or application. Invalid optional metadata is ignored. The legacy generated Felt Room entry receives authored tags once, preserving explicit range clears and recommendation overrides; future edits remain intact.

Direct channel imports previously loaded only the ExternalSound reference, discarding the saved library layer. They now use addLibrarySound so racks, nested processing, macro bindings, MIDI program, levels and bypass states survive. Existing free imports with missing racks continue to recover from matching library entries when selected. Existing customized nonnil racks remain unchanged.

The module's Rack FX link opens the existing sound settings rack editor. The library footer reports the processor count recursively, including bypassed processors. Imported effects remain in their original graph, separate from the three performance effect slots; they are not applied twice. Import reports no longer incorrectly claim that all effects and macros are discarded.

Remaining differences: inferred free-preset taxonomy is not authored Sunday metadata; source-native raw instruments still require reconstruction of their channel processing to match factory variants; unsupported Live processors and current DSP approximations remain documented per sound. Exact audible parity is not established by these metadata and routing fixes.
