# Background audio and interruption recovery

Scope: the iOS/iPadOS app lifecycle around the performance engine. macOS behavior
is unchanged: losing focus releases on-screen notes and the engine keeps running.

This document records decisions and deterministic checks. It does **not** claim a
physical iPad background, call-interruption, battery or thermal pass; those remain
open in #105 and #113.

## Setting

`Settings → Performance → Run Audio in Background` (iPhone/iPad only) is an
explicit opt-in that persists in `settings.json` as `backgroundAudioEnabled`.
Settings files written before the field existed decode with no value, which
resolves to **off** and keeps the previous behavior. The value is session
settings, not patch or setlist data, so it does not change saved performances.

`UIBackgroundModes = audio` is already present in the iOS target's build settings,
so the platform permits continued playback; the setting decides whether StageKeys
asks for it. Bluetooth/Network MIDI and audio-route qualification are separate
gates (#15, #3).

## Policy

`BackgroundAudioPolicy` is a value type in `Sources/SessionSettings.swift`, shared
by both app targets and exercised by `Tests/BackgroundAudioTests.swift`.

| Event | Setting | Action |
| --- | --- | --- |
| App becomes active app-wide (`UIApplication.didBecomeActiveNotification`) | either | Resume only if this app suspended audio for backgrounding, or an interruption left it stopped with resume intent |
| App becomes transiently inactive (Control Center, banner) | on | Nothing |
| App becomes transiently inactive (Control Center, banner) | off | Release notes only; the engine and click choice keep running |
| App enters the background | on | Nothing. Notes, sustain, effect tails, tempo and MIDI ownership continue |
| App enters the background | off, iOS | Release voices, stop the engine, keep the click choice, remember that returning should restart (including a pending startup retry or an interruption that began earlier) |
| App enters the background | off, macOS | Release on-screen notes only; the engine keeps running |
| Interruption begins | either | Release voices and stop audio; keep the click choice; remember whether audio was running |
| Interruption ends with `shouldResume` | either | Restart once, if audio was running before the interruption |
| Interruption ends without `shouldResume` | either | Stay stopped; the performer starts audio explicitly |
| Manual Stop | either | Clears both background and interruption resume intent and the click choice |

The iOS lifecycle is observed through app-wide `UIApplication` notifications
(`didBecomeActive`, `willResignActive`, `didEnterBackground`), not a single
SwiftUI view's `scenePhase`. Shared audio therefore follows the app: one iPad
window entering the background cannot stop the engine while another window is
still active.

An interruption notification without a readable type is treated as a beginning:
suspending is reversible, while ignoring an interruption can leave the session
silent while the UI still reports audio running.

`stopAudio()` is the single suspension path, so a background suspension cannot
leave a second engine, an unresolved patch load, a scheduled startup retry or
voices behind. It preserves the setlist, patch, snapshot, MIDI input observers,
click choice and saved output/buffer preferences, as the existing startup-recovery
document requires. Lifecycle suspension calls `stopAudio(clearResumeIntents:
false, preserveMetronome: true)` and records its own reason, so an interruption
beginning after a background suspension keeps the background intent.
Backgrounding before an interruption ends converts that intent into a foreground
resume and clears it, so the interruption-ended notification cannot start the
engine while the opt-in is off. It also keeps the performer's click choice and
treats a pending bounded startup retry as resumable. A manual Stop uses the
defaults and clears both intents and the click choice.

## Verification

Deterministic (default library gate, no audio device, no scene):

- `Tests/BackgroundAudioTests` covers every scene/opt-in/platform-capability
  combination, interruption begin/end with and without `shouldResume`, the rule
  that a stopped engine is never restarted by a notification, foreground
  activation consuming only the background suspension while preserving the
  interruption resume intent, either event order retaining a pending resume
  reason, guidance text that names the battery cost, and settings round-trip
  plus legacy decoding.
- `python3 Tests/test-library-gate.py .` keeps the new program in the gate.

Not verified here:

- Real backgrounding, screen lock, phone calls, Siri, alarms, route changes and
  Bluetooth MIDI on a physical iPad or iPhone.
- Battery, thermal or media-services-reset behavior.
- Audible continuity of held notes, sustain, tails and tempo across a real
  interruption.
- Any claim that an interruption resume produces sound: a successful
  `AVAudioSession` restart is not a listening test.

Physical pass/fail remains with #105 as the issue requires.
