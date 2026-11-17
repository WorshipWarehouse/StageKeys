# Operation-scoped Audio Unit catalog observations

Implementation follow-up, 2 November 2026, to [saved AU availability](MISSING-AUDIO-UNITS.md). This changes registry-query ownership, not instrument implementation, serialized formats or the release qualification status.

## Behavior

The rack now offers a main-thread, synchronous catalog scope. The first AU availability check in that scope reads the catalog; nested checks reuse the same value. Scope exit, including an error exit, discards it. No catalog snapshot is retained for asynchronous instantiation callbacks, the next user interaction or a later retry.

Patch selection and application wrap their preparation and per-slot configuration in that scope. Standalone patch-resource preparation and standalone controller configuration establish their own scope, so validation before a load request shares the same registry observation. Native-only paths do not evaluate the lazy catalog. Direct validations outside a scope still read fresh availability.

An installed/removed component cannot produce mixed availability observations inside one synchronous operation. The next operation sees a new catalog, and the real loader can still fail after preparation. Component presence does not bypass plugin quarantine: each actual load still calls the recovery journal's `begin`. Native files and sample references are not cached by this scope. Existing request generations, saved-state guards, patch readiness, cancellation and rollback behavior remain in place.

The library and Settings explicit refresh actions still query the catalog directly; their UI observations are separate from a loader operation. A native-only loader scope doing no registry work does not mean other open UI surfaces never request component information.

## Evidence

`InstrumentCatalogScopeTests` is added to the default gate. A counted DEBUG-only catalog provider and generated asynchronous load hooks verify:

- A two-AU patch selection shares **one provider read** across selection preparation, patch application, controller preflight and both load validations.
- A native-only selection leaves that provider unread; stale cancelled callbacks cannot install over the newer patch.
- A later operation observes component removal and rejects before requesting instantiation.
- Standalone multi-slot preparation and standalone controller configuration each use one fresh observation.
- Nested scopes share one observation; an exception releases it; changing the provider's contents does not alter the current scope but is seen immediately after exit.
- Cancelled/missing component checks do not create a quarantine entry.

The count is a control-flow measurement using a generated provider, not a wall-clock benchmark of Apple's registry or third-party bundles. No startup/patch-switch latency, CPU or sonic improvement is claimed. Real registry/catalog refresh latency and large installed-plugin catalogs remain to be measured.

Existing missing-AU, patch readiness, saved-state, recovery-permission, resource-loss and store regressions remain default-gated. See [verification commands, results and frozen source inputs](Completion/au-catalog-operations-verification.json). Generated fixture callbacks do not establish installed-vendor compatibility, physical-device behavior or an interactive UI qualification.

Final local verification: **110 program outcomes: 99 passed, 11 explicit private-fixture skips, zero failures**. One reported pass remains the known private PianoHeldNoteTests early return; it is not exercised piano evidence. Both unsigned release artifact gates passed, along with runner coverage/contract, distribution refusal/content, shell syntax and whitespace checks. All 205 frozen source/test/project hashes were unchanged after verification. C DSP sources were unchanged, so the earlier sanitizer result was not rerun.

## Remaining scope

Registry changes after the synchronous snapshot are handled by actual loader failures and existing recovery; the scope is not a lock on system installation state. Real AU state/version/sound compatibility, crash/hang containment, device/latency/storage behavior, physical mobile, prolonged rehearsal, distribution qualification and the reported intermittent AVFAudio `-1` trigger remain open. Prior evidence records retain their own input sets.

No GitHub issue changes/closure, commit/push, signing, install or distribution were performed.
