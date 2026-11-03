# Library-to-AU editor handoff

After Add Sound commits an Audio Unit from the browser, the Store queues a one-shot editor request. The performance view consumes it on the main queue after the library sheet has dismissed, then presents the existing custom/generic plug-in interface. Audition alone does not queue an editor; non-AU selections clear a pending request.

The request captures patch ID, layer ID, channel index and full external sound identity. Consumption rejects a changed patch, replaced layer/component, invalid index or Patch Lock. Every patch-selection attempt clears the pending request. The editor itself dismisses on patch or external-instrument changes and retains its existing asynchronous callback generation/unit-identity guards. Its bounded load polling covers the rack’s ten-second instantiation timeout instead of giving up after four seconds.

Done uses the existing plug-in-state capture/save path. Generic controls, factory presets and oversized custom-view scrolling continue through PluginInterface. This change does not introduce effect racks or copy plug-in assets/state into app resources.

PluginInterfaceRequestTests verifies one-shot consumption and stale/invalid/locked/non-AU rejection using a synthetic component identity. PluginParameterModelTests, PluginRecoveryTests and StoreTests also pass. Universal Mac and iOS Simulator release artifact gates passed; this model/build evidence is not a physical AUv3/iPad UI test.

## Interface presentation

`PluginEditorModel` owns the presentation rules; `PluginInterface` only renders them. The rules are Foundation-only so they are verified on any platform, without Xcode, a Mac or a third-party plug-in:

- **Sizing.** A plug-in's `preferredContentSize` (or its view's frame) is the declared size, floored at 320×360 and rounded up so no edge is clipped. Zero, negative, NaN and infinite declarations fall back to the floor.
- **Expand/collapse.** On macOS the sheet collapses to a 1000×700 cap, which matches the previous sheet maximum; an editor larger than that scrolls and offers an expand control that lets it use the screen instead. The control is offered only when expanding actually reveals more, so a plug-in that already fits never gets a no-op toggle. iOS has no collapsed cap because the sheet already uses the available screen.
- **Scrolling** stays for the axis that does not fit, so an oversized view is reachable whether it is collapsed or expanded.
- **Reporting.** A plug-in that never becomes ready is reported rather than left on a spinner. Precedence is: blocked in the recovery journal (checked on every poll, so a load failure or the rack's ten-second block is reported when it happens) → a catalog reason such as a missing processor slice, an uninstalled component, or a Mac AUv2 opened on iOS → the editor's own 12-second deadline. Only a timeout offers Retry; a block offers Allow and Retry, which lifts that one block through the existing `allowBlockedAudioUnit` path; an unavailable plug-in offers no action because reinstalling is not something the editor can retry. A plug-in that loads but provides no custom view and no parameters is told apart from one that is still loading.
- **Accessible generic controls.** Each slider or value picker carries the parameter name and its formatted value as its accessibility label and value, and the visible duplicate texts are hidden from assistive technologies so the control is announced once. The factory-preset picker is labelled "Factory preset" with the current preset as its value; the expand control is labelled Expand/Collapse instrument interface with a hint describing the result.

## Verification

- `PluginEditorModelTests` (Foundation only, gated in `Tests/test-library.sh`) covers declaration sanitising, collapsed/expanded sizing, the no-op-expansion refusal, unknown and small available space, the iOS no-cap case, scrolling decisions, the 12-second/120-attempt deadline, diagnosis precedence, and the remedy offered for each report.
- Still manual: a live custom editor and a live generic editor on macOS (including one larger than 1000×700), the same on a physical iPad with an AUv3 instrument, VoiceOver reading the generic controls, and the state/MIDI/EQ round trip described in Issue #53. None of those can run in this Linux workspace.

Issue #53 remains open for live custom/generic presentation on the qualified platforms, physical AUv3/iPad verification and full workflow qualification.

## Audit corrections

The custom view retains its full declared dimensions inside a separately bounded scroll viewport; shrinking the hosted view to the viewport would clip or resize its contents instead of exposing scrollable edges. Retry now asks the host to load a missing unit with patch/layer identity guards and does not start stopped audio. The separate asynchronous custom-view request also has a deadline and rejects late responses after timeout. Model and Store tests cover deterministic rules and retry submission; actual native custom-view scrolling, VoiceOver and callback behavior still require the manual plugin matrix above.
