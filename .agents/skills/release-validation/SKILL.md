---
name: release-validation
description: "Assess StageKeys release readiness across artifact, provenance, hardware and live-performance gates without equating builds to qualification."
---

# Release Validation

Read `Docs/PUBLIC-RELEASE-CHECKLIST.md`, `Docs/RELEASE-ISSUES.md`, `Docs/RELEASE-CI.md` and `Docs/DISTRIBUTION-PROVENANCE.md`. Use the committed Xcode project for release builds; `project.yml` documents inputs. Build outputs belong outside the checkout. Run `Tools/verify-release.sh mac /private/tmp/stagekeys-release-mac` and the simulator variant for unsigned artifact/content/document/notices/icon checks as applicable.

Map each acceptance gate to exact revision, command/artifact and platform. Include complete default library outcomes, parser corpus, runner/gate tests and appropriate sanitizer coverage. Preserve skip counts and known silent private-fixture noncoverage. Verify no private/vendor assets or sessions entered the app bundle; StageKeys ships without sounds. Keep scoped third-party notices, and do not infer a repository-wide MIT license.

Separately qualify supported physical devices, real AU variants, output/audio routes, MIDI reconnect, interruption/sleep/wake, latency, headroom, sustained CPU/memory and prolonged rehearsal using [hardware](../../templates/hardware-testing.md), [audio](../../templates/audio-validation.md) and [release](../../templates/release-qualification.md). Record duration and failure thresholds before the run. A simulator build or generated fake plugin cannot close these gates.

Signing, notarization, uploads, installation and distribution require explicit user instruction; prepare reviewable commands/artifacts first. Do not invoke destructive release operations during ordinary validation. Report readiness by gate with unresolved blockers and exact limits. Never advertise complete compatibility, production readiness or improved fidelity on compilation alone.
