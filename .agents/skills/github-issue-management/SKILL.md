---
name: github-issue-management
description: "Read, assess and prepare StageKeys GitHub issue and PR updates with acceptance-based completion and explicit write authorization."
---

# Github Issue Management

Use the connected GitHub integration first when it supports the operation; authenticated `gh` is the fallback. Resolve repository and issue/PR identity from the actual remote, not assumptions. Retrieve complete body, comments, linked PRs, state and latest commits. Re-read before mutation to avoid overwriting another contributor's changes.

Summarize trigger, expected/observed behavior, reproduction confidence, root cause, affected subsystem and missing acceptance evidence. Search related issues/PRs before proposing duplicates. Dependencies should name the specific blocking capability; priority follows performance/data-loss impact, not merely a large diff. Use [investigation](../../templates/issue-investigation.md) and [PR description](../../templates/pull-request.md).

Require user approval before creating, closing or substantially modifying issues; an explicit current instruction can already supply it. Prepare concrete text first. Do not edit issues just because this skill was loaded. A closure requires every criterion and its platform/hardware qualification, published reviewed implementation and evidence links. Partial fixes should remain open with remaining checks listed; a draft PR is not a completed release gate. Avoid `Fixes #N` when criteria remain incomplete.

Before publishing, inspect complete staged diff, exclude private fixtures/credentials and preserve others' work using [safety](../multi-agent-safety/SKILL.md). Use separate commits/branches for independent infrastructure/app work. Prefer draft PRs and never merge without explicit request. Write multiline CLI bodies through a file, not fragile shell interpolation. Report exact URLs, commit, checks and unresolved items. If authentication or write access fails, retain prepared text locally and state the blocker without exposing tokens.
