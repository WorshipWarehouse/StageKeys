---
name: swift-c-interop
description: "Review StageKeys C DSP and Swift unsafe-memory/callback boundaries for ownership, ABI and real-time correctness."
---

# Swift C Interop

Read `Sources/Bridge.h`, `Synth.h`, `Synth.c`, `CreamCoat.h`, `CreamCoat.c` and Swift callers in `AudioController.swift`/`BuiltinEffectUnit.swift`. The project uses a Swift Objective-C bridging header and C11-family compilation; do not introduce C++ ABI/module assumptions without an actual project requirement and build support.

For each boundary write down allocation owner, element type/count, alignment, mutability, valid lifetime and disposal thread. A `withUnsafe...` pointer must not escape its closure. `Unmanaged` callback contexts require a balanced retain/release policy; cancellation and failure must neither leak nor double release. Check optional/null pointers, zero frames, oversized blocks, channel-count mismatch, integer overflow and partial initialization cleanup.

Match exported signatures and struct layout across headers/callers; do not reinterpret Swift objects or arrays as C storage. Keep buffers valid until the final consumer completes. Audit `memcpy` byte lengths against allocated capacities and use explicit units (frames, samples, bytes). Ensure callback teardown cannot race render access. Pointer validity is required even if the happy path never crashes.

Render callbacks must avoid allocation, locks, file I/O, logging and Swift ownership releases that can destroy large objects. Consult [DSP](../realtime-audio-dsp/SKILL.md) for event/parameter handoff. Use bounds-focused generated tests and AddressSanitizer/UndefinedBehaviorSanitizer; `Tests/test-reverb.sh` is the documented reverb suite, not proof for unrelated unsafe code. Run relevant Swift integration and both affected architectures. Report remaining race/lifetime assumptions and unavailable sanitizer/hardware coverage in [root cause](../../templates/root-cause.md).
