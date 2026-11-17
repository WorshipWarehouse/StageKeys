# Audio Unit recovery settings and durable permission changes

Implementation follow-up, 2 November 2026. This extends [patch readiness](PATCH-READINESS.md) and [resource recovery](RESOURCE-RECOVERY.md); it does not qualify arbitrary third-party plugin behavior or close the release milestone.

## Behavior

Audio Settings now lists blocked Audio Units with names resolved from saved patches, the sound library, the selected Tonic sound and the installed component catalog. An unresolved identity is shown as an unavailable Audio Unit rather than an invented plugin name. **Allow Retry** grants permission to that component only. It does not start audio, change patch selections, instantiate a plugin or unblock other components. The user then retries audio or selects the instrument again. Audio-change errors refresh the known blocked list; opening Settings or using Refresh also consults the catalog for display names.

The Audio Units browser retains its explicit global **Allow Blocked Loads** action, now routed through the same store status/error handling. Global permission changes are refused while loads are still pending. A selective permission change is refused while that same component is still loading; unrelated pending components are not unblocked. Existing timeout/cancellation completion still owns pending counts, so a cancelled callback can take time to finish its journal entry.

Recovery journal updates now build a candidate record, persist it atomically, then replace the in-memory record. A failed begin, finish or permission save cannot publish an unpersisted record. A persistence failure latches further load/permission attempts closed in that instance. Restoring storage access and restarting reopens the journal; pending records from interrupted or unrecorded completion are conservatively converted to blocks by the existing startup policy. Other finishing callbacks may still attempt to record their completion, but they cannot silently clear the persistence-failure latch.

The JSON record shape remains unchanged: component identifiers, pending counts and blocked identifiers only. No plugin state, sample data, credentials or setlist contents are added. Corrupt journals are not cleared or overwritten by decoding failure. Settings displays recovery read/write problems instead of falsely reporting that no blocks exist. Known busy/restart messages are shown without exposing underlying filesystem error paths; retry permission persistence errors retain the existing block list.

## Evidence

`PluginRecoveryTests` extends the existing default-gated journal suite with selective permission persistence, preservation of other blocks, concurrent-load refusal, failed unblock/begin/finish writes, denial of new loads after failed persistence, conservative reopen behavior and exact preservation of corrupt bytes. Write failures use generated directories at disposable journal paths, not permissions changes to user app data.

`PluginRecoverySettingsTests` is added to the default gate. It drives the actual asynchronous instantiate-completion and store recovery paths with generated Apple sampler candidates. Checks include named blocked rows, a stale cancelled load not becoming a new failure, per-component permission without automatic audio restart or layer mutation, a later failure of another component, no-op permission for an already allowed identity, and explicit global clearing. These candidates test lifecycle boundaries; this program does not qualify plugin sound, vendor code, crash containment or physical-device AU operation. Existing patch-readiness tests separately render initialized generated candidates.

See [commands, outcomes and frozen source inputs](Completion/plugin-recovery-settings-verification.json). Earlier evidence records retain their own input sets. The UI compiles in the unsigned Mac and Simulator artifacts; no interactive native-UI walkthrough or physical-device check is inferred from those builds.

Final local verification: **108 program outcomes: 97 passed, 11 explicit private-fixture skips, zero failures**. One reported pass remains the known private PianoHeldNoteTests early return; it is not exercised piano evidence. Unsigned universal Mac and Simulator artifact gates passed, along with runner coverage/contract, distribution refusal/content, shell syntax and whitespace checks. All 203 frozen source/test/project hashes were unchanged after verification. C DSP sources were unchanged, so the earlier sanitizer result was not rerun.

## Limits

Granting retry permission does not install an unavailable plugin, repair its state, or establish that it can load safely. A further failed attempt can block it again. A persistence failure requires storage repair and a fresh journal instance/app restart; Refresh does not erase the file or bypass the latch. External journal edits and simultaneous writers from multiple app processes are not qualified. Existing real AU crash/hang, hardware route/storage/latency, mobile, prolonged rehearsal and actual intermittent AVFAudio `-1` evidence gaps remain open.

No GitHub writes/closure, commit/push, signing, installation or distribution were performed.

Subsequent work: [saved AU availability and replacement](MISSING-AUDIO-UNITS.md) separates missing installation from failed-load quarantine and exposes unavailable patch/library entries without stripping saved state.
