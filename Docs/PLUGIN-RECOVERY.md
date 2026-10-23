# Hosted plug-in loading recovery

Refs #13. Audio Unit instantiation has a ten-second main-queue deadline and a single completion gate. Superseded and late callbacks cannot install an obsolete instrument. Failure/timeout marks the component blocked; interrupted loads discovered on the next launch are blocked before retry. The journal stores component IDs and pending counts only, never AU state or session content. Concurrent loads of one component keep pending ownership until all finish.

The Audio Units browser displays blocked components and provides **Allow Blocked Loads** for an explicit retry. Rescan alone does not clear the block. Corrupt/unreadable recovery data prevents automatic loading rather than silently discarding the protection.

Known AUv3 components on macOS request out-of-process loading. AUv2 still runs in-process: this is not complete crash/hang isolation. A plug-in blocking the main thread inside installation/state restoration can also prevent the deadline from firing; a future helper-process architecture is required for a stronger guarantee. Runtime render crashes/hangs and multi-output/latency compensation are not solved by an instantiation timer. Physical iOS and a real fault-injection plug-in matrix remain release gates.

`PluginRecoveryTests` exercises interrupted loads, explicit retry, persistent failures and concurrent pending ownership with synthetic IDs. Existing real-AU editor/audio/state tests must also pass before merge.
