# Library-to-AU editor handoff

After Add Sound commits an Audio Unit from the browser, the Store queues a one-shot editor request. The performance view consumes it on the main queue after the library sheet has dismissed, then presents the existing custom/generic plug-in interface. Audition alone does not queue an editor; non-AU selections clear a pending request.

The request captures patch ID, layer ID, channel index and full external sound identity. Consumption rejects a changed patch, replaced layer/component, invalid index or Patch Lock. Every patch-selection attempt clears the pending request. The editor itself dismisses on patch or external-instrument changes and retains its existing asynchronous callback generation/unit-identity guards. Its bounded load polling now covers the rack’s ten-second instantiation timeout instead of giving up after four seconds.

Done uses the existing plug-in-state capture/save path. Generic controls, factory presets and oversized custom-view scrolling continue through PluginInterface. This change does not introduce effect racks or copy plug-in assets/state into app resources.

PluginInterfaceRequestTests verifies one-shot consumption and stale/invalid/locked/non-AU rejection using a synthetic component identity. PluginParameterModelTests, PluginRecoveryTests and StoreTests also pass. Universal Mac and iOS Simulator release artifact gates passed; this model/build evidence is not a physical AUv3/iPad UI test. Issue #53 remains open for live custom/generic presentation, expand/collapse, platform compatibility and full workflow qualification.
