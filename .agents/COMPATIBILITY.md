# Discovery and compatibility evidence

Reviewed 2 November 2026. No pre-existing `.agents` or `.codex` framework was found in the starting checkout. No `freebuff` executable was available on PATH; no installation, login or dependency change was attempted. Runtime effectiveness, installed-version behavior and autonomous issue completion are unverified.

## Official source review

Freebuff source revision: `29a8d25386df6e1adda1fec80f87f2d2ae6e206e`.

- [Project discovery implementation](https://github.com/CodebuffAI/freebuff/blob/29a8d25386df6e1adda1fec80f87f2d2ae6e206e/sdk/src/skills/load-skills.ts): scans each valid skill subdirectory for `SKILL.md`; project `.agents/skills` is supported and overrides project `.claude/skills`. Home discovery is a separate opt-in in this SDK revision.
- [Parser](https://github.com/CodebuffAI/freebuff/blob/29a8d25386df6e1adda1fec80f87f2d2ae6e206e/common/src/util/parse-skill.ts) and [schema](https://github.com/CodebuffAI/freebuff/blob/29a8d25386df6e1adda1fec80f87f2d2ae6e206e/common/src/types/skill.ts): plain YAML frontmatter, required name/description, directory-name agreement. Framework uses only those required fields and leaves automatic model discovery enabled.
- [Official Codex skill documentation](https://developers.openai.com/codex/skills/): project `.agents/skills` discovery and required `SKILL.md` metadata support reuse of this one canonical tree. This is documentation-backed format/path support, not a completed fresh-session invocation test.

An older search-indexed Freebuff template README returned 404 at current main. It was not used as authoritative current documentation; the pinned loader/parser above were fetched directly through the official repository API. No undocumented Freebuff agent profiles/configuration were created. No executable agent/MCP configuration is shipped.

## Manual smoke test on an installed Freebuff

1. Record `command -v freebuff`, `freebuff --version`, `freebuff --help`, OS and checked-out StageKeys commit. If those flags differ, use installed help; do not guess invocation options or install packages automatically.
2. Start Freebuff from the StageKeys worktree root using the installed version's documented interactive command. Inspect its skill list/tool discovery. Confirm all 18 names listed in `.agents/validate-skills.py` appear exactly once.
3. Explicitly ask it to load `stagekeys-issue-execution` with its supported skill mechanism. Confirm the complete body loads and relative architecture/testing/template references resolve. Repeat for every specialist. A visible slash command, if supported by that version, may be used; no CLI flag format is assumed here.
4. Give the read-only task: investigate an issue using source and discussion, choose relevant specialists, propose a focused check, and explain which hardware criteria cannot be claimed. Verify it does not load all skills, publish, install, modify app data or claim unexecuted tests.
5. In an isolated branch with synthetic fixtures, authorize a bounded implementation and inspect the diff/test/handoff. Record actual decisions and failures; refine skills only from demonstrated behavior.
6. For Codex, open a fresh session in the same worktree and inspect discovered project skills; explicitly invoke `stagekeys-issue-execution` and check references. No duplicate copies or global config are needed for the documented path.

## Offline validation boundary

`python3 .agents/validate-skills.py` validates this framework's deliberately small metadata subset and local Markdown links with Python's standard library. It does not run Freebuff's TypeScript parser, prove its installed loader behavior, or evaluate a model. The available host skill validator could not run because its PyYAML dependency is absent. No dependency was installed. The project validator checks each of the 18 skills in its restricted metadata subset; that validates structure, not task performance. No runtime compatibility result is inferred from those structural checks.
