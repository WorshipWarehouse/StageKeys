# Audio startup recovery

This document covers the engine-start path only. It does not claim that every
Core Audio route change or third-party plug-in is recoverable.

## States

`PerformanceStore.audioStartup` publishes one explicit state:

| State | Meaning |
| --- | --- |
| `stopped` | No start is in flight. A manual start is allowed. |
| `starting(attempt:)` | The engine start for that attempt is running. |
| `retrying(attempt:delay:failure:)` | A recoverable failure is waiting for its bounded retry. |
| `running` | The engine started and the patch graph was applied. |
| `failed(failure)` | Automatic retries are exhausted or the failure is not retryable. Manual retry remains available. |

The existing `started` flag remains the compatibility signal used by note,
MIDI and UI code. It is true only in `running`; it is set false before a failed
engine is stopped.

`start()` is idempotent while an attempt is in flight or while running.
`stopAudio()` invalidates any scheduled retry with a generation token, so a
late callback cannot start a second engine. The audio graph is built once in
`AudioController.init`; the recovery path does not add another engine, tap or
render source.

## Error translation

`AudioStartupClassifier` maps the error to one user-facing category. It never
puts the raw `localizedDescription` into the message, because that text can
contain paths or device identifiers.

| Category | Typical source | Recoverable |
| --- | --- | --- |
| `outputUnavailable` | No connection, missing device, `ENODEV`/`ENXIO`, route words | Yes |
| `outputBusy` | Observed `'what'` error 2003329396, `EBUSY`, device in use | Yes |
| `formatMismatch` | `kAudioUnitErr_FormatNotSupported`, sample-rate/format text | No |
| `interrupted` | AVAudioSession interruption | Yes |
| `permissionDenied` | Permission/privacy rejection | No |
| `unknown` | Anything else; the numeric code is shown | No |

The message names the last known output route when one is available, then says
what to do: connect or select another output, close the competing app, choose a
supported device setting, or retry. A blank route falls back to “The selected
audio output”.

## Retry bounds

`AudioStartupRetryPolicy` allows at most three attempts with delays of 0.25 s
and 0.75 s. Only recoverable categories are retried. A format or permission
failure stops immediately because waiting cannot change the device setting. An
unknown failure is also not retried blindly; the numeric code and manual retry
remain visible.

Unplug/replug, sleep/wake and route changes arrive as engine configuration
changes. `AudioStartupRecovery` only restarts an engine that was running;
a stopped or failed engine waits for an explicit start so the retry loop cannot
start it while the device is still settling. A route change also re-arms the
saved output selection and hardware buffer for the restart, because the engine
may have moved to a different device; both steps are skipped when no preference
is saved or the device already matches it. A device that rejects the saved
buffer size keeps its current size and the saved preference is retained for the
next route change instead of being erased.

Voice cleanup runs before the engine stops (`panic()` then `audio.stop()`), so
all-notes-off reaches hosted samplers while the graph can still service it.

After the final failure the state is `failed`. The error is not shown through
the old blocking `message` alert. The main window shows a persistent banner with
the explanation, **Retry** and **Audio Settings**. The toolbar shows progress
while starting, and Settings shows the state text plus the same failure and a
**Retry Audio** button.

## What is preserved

- The current setlist, patch, snapshot and unsaved settings are untouched.
- MIDI input and its observers are not restarted by a failed engine start.
- The preferred output UID and hardware buffer are retained. A failed start
  does not clear them; selecting the output and retrying reuses them.
- Failure releases held notes, pedal state and pending MIDI output, then stops
  the engine. The user's saved click (metronome) choice is captured before the
  panic and restored afterwards, so a transient device failure does not turn the
  click off in the session or in `settings.json`. The live Tonic Pad root/sound
  remains selected as intent, while all sounding voices and note/pedal ownership
  are cleared. Only a successful recovery retriggers that pad; manual Stop
  revokes pending resumption. The setlist, patch, snapshot,
  output selection and hardware-buffer preference are not rewritten. A later
  successful start cannot produce stuck voices from the failed attempt.
- No sampler is loaded until `audio.start()` succeeds. On a machine with no
  output device the engine failure is reported before the patch graph runs, so
  the pre-offline sampler-load trap seen in the hosted library runner is not
  reached from the app startup path.

## Verification

Two hardware-free programs are in the default library gate:

- `Tests/AudioStartupTests` covers the classification table, route-safe
  messages, the no-path guarantee for unknown descriptions, the bounded
  backoff, the configuration-change decision and the published state
  transitions.
- `Tests/AudioStartupRecoveryTests` drives the production Store lifecycle with
  an offline engine and injected `NSError`s: the observed busy failure retried
  once then rendering, three bounded attempts with no further automatic retry,
  a sample-rate/buffer rejection reported without retry, cleanup after a
  failure reported once the engine had started, and an injected
  configuration-change cycle that clears held notes, exhausts its retries, does
  not restart a failed engine implicitly, and renders again after an explicit
  retry on the same engine and rack instances. It also checks that the
  setlist/settings bytes, selected patch, snapshot and click choice survive.

Neither program is a device test. `debugStartFailure` and
`debugFailureAfterEngineStart` are DEBUG-only injections; the store's
manual-rendering route means no output device is opened.

| Scenario | Deterministic coverage here | Physical macOS check still required |
| --- | --- | --- |
| Unavailable output | `-10876`, POSIX `ENODEV`/`ENXIO` classification and the bounded attempt count | Unplug the AudioBox during playback and confirm the message names it |
| Output busy / in use | Observed `2003329396` retried once and then running | Open MainStage plus Sunday Keys on the AudioBox and confirm recovery |
| Sample-rate/buffer mismatch | `kAudioUnitErr_FormatNotSupported` reported once with the route-safe message | Force a mismatched device setting and confirm no automatic retry loop |
| Partial initialization | Failure thrown after the engine started leaves the engine stopped and the state `failed` | n/a (software state only) |
| Session/settings preservation | Setlist and settings bytes, patch, snapshot and click choice unchanged | Confirm the audible patch and output are unchanged after recovery |
| Unplug/replug | Injected configuration change restarts only a running engine and never a failed one | Real unplug, replug and note-on after the device returns |
| Sleep/wake | Same injected configuration path; a deliberate Stop stays stopped | Wake the Mac mid-session and confirm audio and MIDI resume |
| Stuck notes | Held notes, hardware keys and pedals cleared; recovery renders | Listen for stuck voices across a real failure and retry |

A physical reproduction with the AudioBox USB 96 and competing apps, a real
unplug/replug, and sleep/wake remain hardware checks. This document does not
claim those were performed; issue #110 stays open until that evidence exists.

See [retained pad intent during recovery](PAD-RECOVERY-INTENT.md) for the generated regression and explicit Stop behavior. The pad retriggers; phase continuity and physical unplug/wake recovery are not established.
