---
name: persistence-and-conversion
description: "Change StageKeys saved data, migrations, import/export, sampler references or partial MainStage conversion without silent data loss."
---

# Persistence And Conversion

Inspect `Models.swift` validation and Codable defaults plus `SetlistLibrary.swift`, `SessionSettings.swift`, `SoundLibrary.swift`, `LibraryBackup.swift` and Store save/load callers. Identify the on-disk format, version, authoritative bytes and recovery/backup locations before editing. Use synthetic old/new documents, never private sessions as public fixtures.

Validate the entire candidate before publishing it; atomic replacement must preserve the last valid file if encoding/write/rename fails. Do not overwrite corrupt input before retaining recovery evidence. Test interrupted writes, malformed/oversized input, path traversal/symlink cases, unavailable storage and retry. Preserve unknown/unsupported fields when the documented format requires it; make migration defaults explicit and verify restart, duplicate and export/import round trips.

For conversion inspect `MainStagePatch.swift`, `MainStageProcessing.swift`, `EXSNative.swift`, `StageKeysSampler.swift` and `SamplerInterchange.swift`, then `Docs/CONVERSION-STATUS.md` and `Docs/SOUND-FORMATS.md`. Separate source archive, partial translation, captured rendering and playable conversion. Inventory dependencies and unsupported synths, routing/buses/effects/macros/MIDI rather than flattening them silently. Preserve required original bytes and compare hashes; file existence does not prove a readable sample or compatible plugin state.

Use `SessionRecoveryTests`, `TransactionalImportTests`, `MainStagePreflightTests`, `LibraryBackupTests` and the directly affected format test. Read fixture requirements; report private-fixture skips distinctly. Avoid changing file extensions or schema to mask unsupported behavior. Use [persistence validation](../../templates/persistence-validation.md) to report exact round-trip and failure guarantees, migration decision and remaining loss risks.
