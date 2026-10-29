# Oversized session recovery

Refs #20. Normal session/backup loading remains limited to 64,000,000 bytes, with schema validation and regular-file checks. Previously explicit recovery also tried to load the damaged primary through that bounded reader; a larger damaged file therefore prevented restoration of an otherwise valid previous session.

Recovery now validates the bounded backup first, copies an existing regular primary to a unique `.damaged-<UUID>` file using filesystem copying, then atomically replaces the primary with the validated backup. It does not decode or load the oversized damaged primary into memory. The previous backup remains intact. Both live and dangling symbolic links, directories and invalid backups are rejected. A failure to preserve the primary aborts recovery before replacement. Available disk space and filesystem copy permissions are still required; this is not a disk-full recovery guarantee.

`SessionRecoveryTests` generates an original sparse 64,000,001-byte damaged file, verifies its SHA-256 before/after preservation, and checks restored session bytes, retained backup, unsafe links and invalid-backup refusal. Existing startup/autosave protection tests remain. These tests use disposable data and do not alter installed user sessions.

This addresses the oversized-primary recovery gap only. Full migration/undo coverage and clean physical-device portable restore remain separate acceptance work in #20.
