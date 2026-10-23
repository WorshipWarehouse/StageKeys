# Independent patch builder — later milestone

Refs #24. The AI builder remains after the core v1 conversion/audio/stability gates. It will use StageKeys' own documented patch schema and the user's installed, authorized content. It will not call or scrape Sunday Keys' builder. No remote model/provider, account, key or data sharing is enabled by this foundation.

`PatchDraftPlan` schema 1 is a provider-independent data proposal: name plus 1–15 unique installed-library IDs, bounded gain/pan/key ranges and optional validated three-slot effect arrays. It accepts no script, shell command, download, executable path or remote-content instruction. The host supplies actual device availability. Missing/ambiguous/unavailable content produces a missing-ID preview with no patch, never a fallback instrument. Existing source effects/racks remain unless an explicit valid effect proposal replaces the public effect slots. Preview builds independent identities and cannot write to Store, files or audio.

Future flow: request → local/manual or explicitly opted-in remote proposal → strict schema/availability validation → preview and warnings → isolated audition → edit/compare/undo → explicit Confirm. The live patch remains unchanged until Confirm. Remote opt-in must explain exactly what leaves the device; never include samples, plugin state, credentials or complete private sessions by default. No automatic downloads/purchases or generated code execution.

Before enabling an AI UI, add musical-usefulness evaluations, reproducibility, output headroom checks, latency/cost limits, cancellation and an offline/manual fallback. This PR supplies the validated local boundary and tests, not an implemented AI generation service or release-ready builder.
