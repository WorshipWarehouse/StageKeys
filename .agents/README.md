# StageKeys agent skills

The canonical framework is `.agents/skills/`, with 18 Markdown-only skills. No executable agent configuration, MCP server, dependency install or duplicate skill tree is required. The existing root `AGENTS.md` remains authoritative and unchanged. Start issue work with `stagekeys-issue-execution`; read only relevant specialists, then prepare an evidence-backed handoff. Skills guide an agent; they do not guarantee autonomous correctness or authorize external writes.

## Setup and discovery

Clone the repository, enter its root and use a trusted, already installed Freebuff version with project skill support. Freebuff discovery support was verified by reading the official loader/schema at revision `29a8d25386df6e1adda1fec80f87f2d2ae6e206e` on 2 November 2026: it scans project `.agents/skills/<name>/SKILL.md`. Metadata uses only required `name` and `description`. There is no installed Freebuff executable in the validation environment, so runtime listing/invocation and installed-version compatibility remain unverified. See [compatibility and manual procedure](COMPATIBILITY.md). Do not install or change global configuration without approval.

Codex's official skill documentation also describes `.agents/skills/` project discovery. The same Markdown files can be used without copying them; native discovery/invocation in a fresh Codex session still requires a smoke test. No project-wide license is asserted; repository licensing remains unspecified as described in `AGENTS.md`.

## Routing

Always start with issue execution, architecture, testing and work ownership. Load a specialist when its decisions are needed, not all 18 at once.

| Trigger | Specialist skill(s) |
| --- | --- |
| Swift, SwiftUI, AppKit/UIKit or concurrency | [Swift/Apple](skills/swift-apple-development/SKILL.md) |
| Glitch, graph, render/DSP change | [DSP](skills/realtime-audio-dsp/SKILL.md), [profiling](skills/audio-performance-profiling/SKILL.md) |
| Sustain, routing, MIDI Learn, device events | [MIDI](skills/midi-integration/SKILL.md), [performance](skills/performance-engine/SKILL.md) |
| Layer, patch, snapshot, loading | [performance](skills/performance-engine/SKILL.md) |
| Saves, migration, import/export, formats | [persistence](skills/persistence-and-conversion/SKILL.md) |
| Layout, navigation, accessibility | [UI](skills/ui-ux-validation/SKILL.md) |
| Missing reference behavior | [reference](skills/reference-behavior-analysis/SKILL.md), [REA](skills/rea-reference-investigation/SKILL.md) only when needed |
| Issue enrichment, publication, PR | [GitHub](skills/github-issue-management/SKILL.md) |
| Concurrent/dirty checkout or integration | [safety](skills/multi-agent-safety/SKILL.md) |
| Release qualification | [release](skills/release-validation/SKILL.md) |
| AU discovery, state, editor, lifecycle | [AU hosting](skills/audio-unit-hosting/SKILL.md) |
| Pointer, buffer, C callback | [interop](skills/swift-c-interop/SKILL.md), DSP |
| Xcode/CI failure | [build automation](skills/xcode-build-automation/SKILL.md) |

Entry points: [issue execution](skills/stagekeys-issue-execution/SKILL.md), [architecture](skills/stagekeys-architecture/SKILL.md), [testing](skills/testing-and-debugging/SKILL.md). Shared [standards](STANDARDS.md), [templates](templates/) and [checklists](checklists/) keep reports comparable.

## Assigning the first issue

After fetching the desired remote branch, make a clean dedicated worktree and run Freebuff from that worktree's repository root. Verify the skill list first using the procedure in `COMPATIBILITY.md`. Then send:

> Load `stagekeys-issue-execution`. Investigate https://github.com/WorshipWarehouse/StageKeys/issues/NUMBER and all comments/linked evidence. Read AGENTS.md. Use only the specialists needed for that issue. Preserve other contributors' work and private data. Reproduce the defect, identify the root cause, implement the authorized bounded fix, and run the directly affected tests. Return acceptance criteria with evidence and remaining qualification. Do not publish, close issues, install dependencies or merge without my explicit instruction. If required hardware is unavailable, mark it unverified rather than simulating a completed hardware gate.

Replace NUMBER with the assigned issue. Start with a bounded software criterion; do not assign a broad release/hardware umbrella expecting a code-only closure. REA is optional. Use `.agents/templates/issue-completion.md` for handoff.

## Validation

From repository root: `python3 .agents/validate-skills.py`. It checks the exact 18-name inventory, metadata subset, directory agreement, missing local links, empty scaffolds and infrastructure scope. It is an offline project validator, not Freebuff's runtime parser. The recorded validation and infrastructure-only diff are in [implementation report](IMPLEMENTATION-REPORT.md).
