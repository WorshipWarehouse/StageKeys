# Independent keyboard play and display settings

Issue #109 follow-up, 3 November 2026. This implements its separate on-screen playability and played-note visualization controls; it does not establish complete performance-settings parity.

## Investigation and plan

At baseline `309f311`, PianoKey always called Store note-on/off and colored keys from `isNoteHeld`. Performance settings exposed only silent-sound suppression and layer ranges. There was no independent saved preference for either behavior.

Settings → Performance now has **On-Screen Keyboard Playable** and **Display Played Notes**, both enabled by default. Disabling screen play releases screen-owned notes and its sustain contribution immediately; hardware note and pedal ownership is retained, including when the same pitch is held from both inputs. Hardware MIDI remains playable. Displaying notes is independent: hiding highlights does not release or mute anything. Re-enabling highlights reflects the notes still held.

The Store enforces screen admission in addition to the SwiftUI disabled state, so gesture/accessibility entry cannot bypass the preference. Note-offs remain admitted. The shared PianoKey implementation covers the main keyboard and layer-range editor; disabled keys retain their accessible note names and disabled state. Physical VoiceOver/touch/focus walkthroughs remain unverified.

The two optional Boolean fields are appended to `SessionSettings`; absent fields resolve to the former enabled behavior. Store save/reload persists both choices through the existing recoverable settings writer. Setlist/patch/sample formats, hardware routing and render-thread code are unchanged. These are application preferences rather than exported patch settings.

## Verification and remaining scope

`KeyboardPerformanceSettingsTests` uses generated sounds and a virtual CoreMIDI source through the production input handler. It covers independent display/play choices, same-pitch ownership, hardware and screen-only sustain, hardware note-on/off with screen play disabled, restart persistence and missing-field defaults. It runs in the existing default library gate. MIDIInputTests and MetronomeSettingsTests are adjacent focused checks.

Issue #109 remains open for bounded previous/next preload windows and eviction, measured native/AU resource budgets, dynamic MIDI-FX ranges, optional per-sound meters, failure/external-storage qualification and prolonged physical performance. No reference application was inspected for this change, and no proprietary content is used.

Final local checks: three focused programs passed; the full native arm64 suite reported 108 passes, 11 explicit skips and zero failures. The optional private-piano case remains unexercised despite reporting pass. Universal Mac and generic Simulator artifact gates passed. Simulator runtime and physical accessibility walkthroughs were not exercised. All 218 frozen app/test/project/workflow inputs matched after verification. Exact commands, log hashes and input hashes are in [verification](Completion/keyboard-performance-controls-verification.json).
