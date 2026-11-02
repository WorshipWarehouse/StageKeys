---
name: xcode-build-automation
description: "Build and troubleshoot the actual StageKeys Xcode targets and CI safely, preserving committed project authority."
---

# Xcode Build Automation

Inspect `StageKeys.xcodeproj/project.pbxproj`, `project.yml`, `Docs/RELEASE-CI.md`, `Tools/verify-release.sh` and `.github/workflows/distribution.yml`. Check `xcodebuild -version`, `xcodebuild -list -project StageKeys.xcodeproj` and supported SDKs/destinations when troubleshooting. Current targets/schemes are `StageKeysMac` and `StageKeysMobile`; confirm before scripting. No Swift package dependency should be invented to explain a framework build failure.

Use existing wrappers first: `Tools/verify-release.sh mac /private/tmp/stagekeys-build-mac` or `Tools/verify-release.sh simulator /private/tmp/stagekeys-build-simulator`. Their gates inspect executables, platform metadata, content and document/icon declarations. Keep DerivedData/output paths outside checkout and unique across concurrent runs. For a direct diagnostic build derive arguments from the wrapper; record scheme/configuration/destination/architectures/signing settings and full log path.

Find the first real compiler/linker error rather than treating every service warning as the cause. Distinguish SDK/destination availability, stale simulator services, bridging headers, deployment APIs and actual source regressions. Avoid deleting global caches or regenerating the project as a first response. If modifying project inputs, keep the authoritative committed project aligned intentionally.

Core library tests are standalone programs; do not assume `xcodebuild test` discovers them. Run [testing](../testing-and-debugging/SKILL.md) commands. Physical-device installation, provisioning changes, signing/upload and distribution require authorization. Record `.xcresult` bundles only when a real test action produces them; build logs are not result bundles. CI success must match the pushed revision and cannot imply physical-device readiness.
