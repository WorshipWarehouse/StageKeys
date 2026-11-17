---
name: swift-apple-development
description: "Implement StageKeys Swift, SwiftUI and Apple framework changes consistent with its deployment targets and concurrency boundaries."
---

# Swift Apple Development

Inspect `project.yml` and committed project build settings: the recorded baseline uses Swift language mode 5.0, macOS 13 and iOS 16 deployment targets. Confirm before adopting APIs or concurrency syntax; current Xcode version does not raise minimum OS support. Use availability guards and existing platform branches for AppKit/UIKit integration.

Trace UI mutations through `PerformanceStore` actions. Preserve main-thread ownership of observable state and graph coordination; inspect callback queues before publishing. Capture identity/generation as well as weak ownership in asynchronous plugin callbacks: weak self alone does not reject a stale patch/layer result. Balance timers, observers and callbacks at cancellation and teardown. Avoid retain cycles in framework delegates and view-controller hosting.

Use throwing APIs or explicit results where caller decisions depend on success. Do not hide native failures with `try?` if that would publish unapplied settings or save invalid state. Keep runtime acceptance separate from persistent model commit. Prefer small value models/protocol boundaries where they improve testability; avoid broad refactors during a recovery fix.

Inspect Swift/C pointer lifetimes with [interop](../swift-c-interop/SKILL.md) and audio callbacks with [DSP](../realtime-audio-dsp/SKILL.md). A main-actor task is not permission to block startup with disk or vendor work; document unavoidable synchronous Apple calls and keep cancellation claims precise.

Run focused core tests and the relevant unsigned app artifact gate from [build automation](../xcode-build-automation/SKILL.md). Verify both platform branches when changing shared SwiftUI/framework code. Report compiler warnings, unsupported platforms and missing interactive validation separately; a successful macro/core compile does not validate AppKit/UIKit lifecycle.
