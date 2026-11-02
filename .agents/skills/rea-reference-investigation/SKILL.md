---
name: rea-reference-investigation
description: "Use optional REA investigation for authorized reference artifacts or runtime behavior after checking installed capabilities."
---

# Rea Reference Investigation

Use this only when reference artifact/runtime evidence is needed, not routine StageKeys repository architecture work. Read existing `Docs/DEEP-UI-AUDIT.md`, `Docs/SOUND-FORMATS.md` and issue evidence first. Define the concrete question, user-authorized app/files, allowed operations and artifact destination. A local vendor file is not redistribution permission.

Verify installed REA executable, version, help and doctor/capability output before selecting commands. Use `command -v rea` and the discovered executable's `--version`/`--help`; inspect supported subcommand help. If absent, report that and continue source/document analysis where useful; do not install dependencies or invent REA commands. If a host reverse-engineering skill is available, read it before tool use. Do not assume an older recorded version or cached session still applies.

Choose bounded read-only metadata/format inspection or authorized visible runtime observation supported by that version. Record target/app hash and version, platform, entitlement state, command/options, time, output artifacts and limitations. No decryption, DRM/authentication/entitlement bypass, restricted downloads or proprietary source/art/sample copying. Keep private material outside the public checkout; commit only reviewed sanitized findings and synthetic fixtures.

Classify findings using [reference analysis](../reference-behavior-analysis/SKILL.md). Static strings/imports suggest possibilities, not executed workflows or sonic equivalence. Runtime observations need exact actions and, for audio, route/sample-rate/block-size/MIDI/gain conditions. If access is blocked or capabilities insufficient, mark UNKNOWN and propose the next authorized discriminating observation. Integrate findings into the assigned issue's evidence map rather than claiming complete parity.
