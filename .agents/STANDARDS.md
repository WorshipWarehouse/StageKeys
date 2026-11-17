# Shared development standards

Read root `AGENTS.md` first. User authorization persists; skills add no blanket permission for GitHub mutation, installation, signing or deployment.

- Root cause: capture a concrete trigger and first incorrect state transition; distinguish observations, documentation and hypotheses. A failing generated regression can prove a bounded host defect, not a hardware/vendor reproduction.
- Architecture: trace view → Store → runtime/persistence ownership. Commit accepted state deliberately; pending callbacks need identity/generation guards. Preserve current supported platforms and document unsupported behavior.
- Audio: no allocation, locks, I/O, logging or graph work on render threads. Describe control-to-render handoff and teardown lifetime. Measure performance under matched conditions.
- MIDI: retain source/channel/note ownership through splits, transpose, sustain and replacement. Test note-off/disconnect/Panic and explicit Program Change opt-in. Device enumeration must not override manual Stop.
- Data: validate candidate data before publishing; preserve last valid bytes on failure. Test migration, corruption and round-trip. Archive/partial conversion/playable result are distinct outcomes. Never commit private libraries, sessions, credentials or plugin state.
- Platforms: compile relevant shared branches and qualify hardware separately. Simulator/unsigned artifacts do not prove device usability, signing or install readiness.
- Tests: select actual documented checks; run affected checks after final edits. Separate failure, skip, absent fixture and unexecuted checks; preserve exact commands/revision and limitations.
- Work ownership: inventory dirty/untracked files, use isolated branch/worktree, stage intended scope and inspect complete diff. Never reset/clean/overwrite another agent's work. Coordinate exclusive write paths if delegation is authorized.
- Completion: map every acceptance criterion to reproducible evidence or an open gap. Prepare reviewable commits/PR text. Close only fully satisfied issues with authorization; don't use auto-closing PR keywords for partial work.
