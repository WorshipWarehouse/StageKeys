---
name: multi-agent-safety
description: "Protect concurrent StageKeys work with bounded ownership, dedicated branches/worktrees and reviewable Git changes."
---

# Multi Agent Safety

Read `AGENTS.md` and inventory `git status -sb`, `git diff`, untracked files, current branch, worktrees and remote before mutation. Record which changes predate the assignment. Never reset, clean, stash, overwrite, force-push or discard another contributor's work to get a clean tree. A dirty tree is information, not a defect.

Use a dedicated `codex/` branch or worktree for independent work. Create worktrees outside the source checkout where possible. If infrastructure-only scope is assigned, change only `.agents`/approved documentation and verify no app/test/build-source diff. Do not regenerate the committed Xcode project unnecessarily. Worktree isolation separates indexes and branch history but not external app data, system devices or output directories; isolate fixtures and build paths too.

When delegation is authorized, give each agent a concrete question, allowed evidence, exclusive write paths, prohibited operations and requested evidence/uncertainty format. Avoid concurrent writers to one file; reconcile patches and contradictions centrally. Do not launch agents just because slots exist. Model agreement is not a test result.

Before staging inspect changed/untracked content and provenance, especially private samples, AU state, session data, credentials and generated binaries. Stage explicit intended paths when work is mixed. Review `git diff --cached --check` and `git diff --cached --stat`, then the actual diff. Commit only authorized scope; do not automatically merge or publish. On conflicts stop destructive operations, preserve both inputs and resolve against tests/source evidence. [Implementation plan](../../templates/implementation-plan.md) records ownership and integration checks.
