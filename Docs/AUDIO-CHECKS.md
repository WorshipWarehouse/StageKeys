# Local audio checks

On Mac, choose **Help → Record 30-Second Audio Check**, play the affected sound, then choose **Help → Stop Audio Check**. Recording stops automatically after 30 seconds. A completion message shows the local WAV path in the application's `Audio Checks` folder alongside its user data.

The tap records StageKeys' stereo output after effects, the output limiter and output headroom. It does not access a microphone or other apps. The take keeps the engine's sample rate and floating-point samples. It does not modify or export a library preset or source sample, and it is not uploaded or included in the optional sound library.

Disk writes run on a separate serial queue. The pending-buffer limit prevents an unbounded recording backlog; a write/backlog failure is reported instead of silently treating a dropped-buffer take as valid. Accepted buffers finish writing before the WAV closes. Starting another check is blocked until the current file has closed. Stopping playback finishes any active check.

For attack diagnosis, play a few isolated notes with the pedal released, then repeat with sustain. Compare the resulting file with the sound heard live, at the same output level. A similar offline/reference clip alone cannot certify that a live attack problem is fixed.

`AudioDiagnosticRecorderTests` checks stereo sample order, sample preservation, exact frame limits, validation and repeated stop behavior. No private sound fixture is needed for that test.

## Temporary master limiter comparison

Audio Settings → Audio → **Bypass Master Limiter (Temporary)** toggles only the output limiter’s bypass property. The graph, master/channel levels, effects and 1 dB output headroom remain unchanged. Re-strike notes after toggling for the attack comparison. This switch is not stored in settings or setlists; the limiter is active again after restarting StageKeys. Audio checks capture whichever limiter state is currently selected.
