# Modulation wheel input ownership

Refs #18. The on-screen CC1 wheel holds its position when released, quantizes to all 128 MIDI values and accumulates movement smaller than one CC step. Hardware or snapshot changes during an active pointer drag now rebase the remaining relative motion instead of jumping back to the stale drag-start value. Closing the view resets pointer ownership, not CC1. The help text makes low/high orientation and current MIDI value explicit; VoiceOver retains adjustable steps.

`ModulationWheelTests` covers endpoint clamping, zero-motion click/release, sub-step accumulation and hardware handoff. Geometry/lighting parity and the complete reference page audit still need visual verification. The Mac locked during the attempted Sunday Keys reinspection, so no new reference observation is claimed. Existing `DEEP-UI-AUDIT.md` and `PARITY-STATUS.md` remain the recorded baseline.
