# Bounded outstanding Audio Unit requests

Implementation follow-up for hosted-instrument reliability, 2 November 2026. This extends [loading cancellation](AUDIO-OPERATION-CANCEL.md). It does not qualify vendor process containment or establish an overall audio CPU/memory budget.

## Reproduced defect and behavior

A generated stalled-backend regression submitted 33 AU instantiation requests despite cancelling each preceding request. Existing generation cancellation protected attachment and playback ownership but imposed no submission bound. The baseline failed the new outstanding-request assertion.

The host now admits at most **32 outstanding AU instantiation requests across rack instances in the process**. That allows two full 16-slot request sets: 15 performance slots plus Tonic. This is a host admission policy, not a measured optimal hardware setting. New requests at capacity reject before recording a new journal load or calling the backend. Native file/instrument loading remains outside this AU-request budget.

Each accepted backend request owns a unique ticket. Stop, supersession, a graph recovery/reset or logical timeout does not release it: those operations cannot prove Core Audio's request has ended. Only the backend callback releases its own ticket on the main thread, including callbacks arriving after timeout or owner disappearance. Duplicate callbacks cannot release another request's capacity. A backend that never calls back keeps its ticket; opening/resetting a rack cannot bypass the process-wide bound.

The existing ten-second host timeout remains unchanged in release builds. It can complete/quarantine a current load without falsely declaring its backend work finished. A later success cannot attach a timed-out candidate or complete the host result twice. Cancellation still follows its existing superseded-result policy rather than automatically creating a plugin-failure block.

Capacity rejection gives fixed, actionable feedback: earlier loads are still finishing; wait before retrying, or save work and restart if they never finish. A single-layer rejection can retain the previous native sound and session. Whole-patch failure follows the existing stopped/manual-retry policy; its final message no longer claims a previous sound is available after stopping. The internal capacity domain is a fixed allowlisted support-diagnostic value, not an arbitrary vendor/path string. The diagnostic record shape is unchanged.

## Evidence

`PendingAudioUnitLoadTests` is in the default gate. Generated stalled callback hooks exercise the actual request/journal/generation paths without launching vendor plugins. Checks cover:

- Baseline submission growth and the new 32-request admission boundary.
- Rejection from another rack in the same process, and preservation of the count across graph recovery/reset.
- Retained native unit identity, graph generation, held/pedal intent, rendered level and exact session bytes on rejected single-layer replacement.
- Whole-patch capacity failure with correct stopped-state guidance; a native patch can still recover while old requests remain outstanding.
- One returned callback reopening exactly one slot, cancellation/draining without quarantine, and no ticket release from mere logical timeout.
- A late timed-out success never attaching/completing twice; an old duplicate callback not releasing a newer ticket.
- Explicit unblock after timeout and a subsequent initialized generated sampler producing actual audio.
- Support-diagnostic round-trip with the capacity domain and no generated private component name.

Timeout coverage uses a DEBUG-only shortened timer; the production deadline remains ten seconds. Rendering uses original generated WAVs, stereo 48 kHz offline and 512-frame blocks, with isolated per-program app data. See [verification commands, outcomes and frozen input hashes](Completion/au-load-admission-verification.json). Earlier evidence records retain their own input sets.

Final checks on the frozen 209 source/test/project inputs reported **103 passed, 11 skipped, zero failed**. The private-piano case still reports a pass without its optional fixture and remains unexercised. Unsigned universal Mac and Simulator release artifact gates passed; these are not device/runtime qualification.

## Limits

This bounds explicit in-flight host instantiation requests, not active/retired DSP graphs, plugin-internal allocations, subprocess counts, CPU usage or every Core Audio registry operation. It does not kill or preempt vendor work, auto-queue new requests or guarantee a hung backend will return. Restart guidance is a recovery option, not proof that all vendor services are terminated. Actual process crash/hang containment, real plugin resource measurements, device/latency/storage behavior, physical mobile, prolonged rehearsal, distribution and the original intermittent AVFAudio `-1` trigger remain unqualified.

No GitHub issue changes/closure, commit/push, signing, installation or distribution were performed.
