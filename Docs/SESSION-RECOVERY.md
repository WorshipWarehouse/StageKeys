# Session recovery

Refs #20. Setlist and settings saves retain a validated `.previous` copy before an atomic replacement. Identical writes do not rotate the backup. Invalid, oversized, symlink or unsupported-version session files cannot replace a last-known-good copy.

Previously a failed startup load displayed an error but continued with defaults; the resign-active autosave could overwrite the unreadable session. Startup failure now blocks automatic session/settings writes. Settings displays **Recover Previous Session**. Recovery validates the previous copy first, retains the damaged bytes under a unique `.damaged-*` filename and restores the known-good session. Restored settings require a restart to apply the original routing safely. Failed recovery does not replace the current files. If no previous copy exists, retain the files and restore a portable backup; no silent reset is offered.

The two session files are each atomic, not a multi-file transaction. Portable library recovery, power-loss guarantees across volumes and every historical migration fixture remain separate release verification. `SessionRecoveryTests` exercises actual Store startup/autosave protection and exact byte retention with synthetic sessions; private user files are never modified by the test.
