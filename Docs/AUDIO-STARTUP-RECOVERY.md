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
start it while the device is still settling.

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
- Failure stops the engine and calls `panic()`, which clears held notes, pedal
  state and pending MIDI output and stops the metronome and tonic pad. The
  setlist, patch, snapshot and output selection are not rewritten. A later successful start cannot produce stuck
  voices from the failed attempt.
- No sampler is loaded until `audio.start()` succeeds. On a machine with no
  output device the engine failure is reported before the patch graph runs, so
  the pre-offline sampler-load trap seen in the hosted library runner is not
  reached from the app startup path.

## Verification

`Tests/AudioStartupTests` is in the default library gate. It covers the
classification table, route-safe messages, the no-path guarantee for unknown
descriptions, the retry bounds and the published state transitions. It needs no
audio hardware or private fixture.

The hosted macOS library job compiles and runs it with everything else. A
physical reproduction with the AudioBox USB 96 and competing apps, a real
unplug/replug, and sleep/wake remain hardware checks. This document does not
claim those were performed; issue #110 stays open until that evidence exists.
