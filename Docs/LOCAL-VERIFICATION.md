# Local release verification

Run the existing Swift test list with a single testable core module:

```
python3 Tests/run-local-library.py . /private/tmp/stagekeys-local-tests
```

An optional trailing list selects tests. The runner reads the same Sources and default test list as `Tests/test-library.sh`, compiles the complete core once with DEBUG/testable access, then compiles and executes each unchanged test body against it. Every run uses a fresh private data directory; no user session, source library or original samples are overwritten. This changes test build organization, not test assertions. The original shell runner remains available for monolithic builds and private fixture arguments.

The default list also covers the native C DSP regressions (`AudioEffectsTests`, `ChannelDSPTests`, `ChannelPanicTests`, `RackTests`, `SynthTests`), which link the C objects built by the same script and need no Swift sources or audio hardware. The remaining C programs run in the `Tests/test-reverb.sh` ASan/UBSan suite, which is a separate CI job.

Two tests stay on demand: `AudioDeviceTests` and `LivePatchContentTests` require a live output device, which hosted runners may not provide. Run them on a Mac with `Tests/test-library.sh AudioDeviceTests LivePatchContentTests`.

`AudioGraphTests`, `ExternalAudioTests`, `SamplerInterchangeTests` and `SetlistLibraryTests` take a writable path. Both runners now create a private `scratch/<test>` folder under the build directory and pass it, instead of requiring a hand-written argument. `MIDIInputTests` and `ExternalMIDITests` use virtual CoreMIDI endpoints only, so they run in the default gate alongside the other synthetic MIDI tests.

The remaining programs stay on demand because they need hardware, private content or a specific installed third-party Audio Unit:

| Test | Why it is not in the default gate |
| --- | --- |
| `AudioDeviceTests` | Enumerates and guards a live output device. |
| `LivePatchContentTests` | Requires live streaming through the audio device. |
| `RealtimePianoTests` | Requires live audio plus `STAGEKEYS_PIANO_PRESET`; prints SKIP without it. |
| `CapturedSoundPlaybackTests` | Requires a private converted-capture library. |
| `FeltPianoFidelityTests` | Requires the private Felt Piano source and samples. |
| `LivePianoFidelityTests` | Requires private piano libraries and live streaming. |
| `OutputHeadroomTests` | Requires private converted library sounds. |
| `SoundIdentityTests` | Requires private converted library sounds. |
| `AudioUnitTests` | Requires an installed third-party Audio Unit such as OB-Xd. |

Run a documented on-demand test explicitly, for example `Tests/test-library.sh AudioDeviceTests LivePatchContentTests`; the same names work as trailing arguments to `run-local-library.py`. `Tests/test-library-gate.py` fails when a test program is neither in the default gate nor in the table above, or when a path-taking test loses its scratch-folder handling, so a program cannot become silently ungated again.

`PatchGainTests` is back in the default gate after #80 made single-file samples resident before loading. The earlier failure was periodic silent gaps during sustained playback, not moving note onset. On 29 October, 20 consecutive continuity runs and 20 gain runs passed: longest digital-silence run 50 frames (initial onset), +6 dB ratio 1.9952624 and −6 dB ratio 0.5011872. These synthetic offline measurements do not substitute for hardware latency or full library listening checks.

The fast Python runner executes the same five C regressions after the default Swift list. An explicit Swift test selection remains a focused run.

`PianoHeldNoteTests` runs by default but returns immediately unless `STAGEKEYS_PIANO_PRESET` names a private Steinway preset, the same way `EXSImportTests` skips without its fixture arguments.

Release checks still include universal Mac and iOS Simulator builds, `Tests/test-reverb.sh` with ASan/UBSan, applicable Python corpus/evidence checks, and source/bundle content validation. A simulator build is not physical iPad qualification. Local checks do not alter GitHub billing or report hosted CI as green.

The PR matrix records the exact commit SHA for each revision. Completed DSP/build results may be reused only for byte-identical complete input sets; cache entries retain the originating PR/SHA and input SHA-256. Distinct code, test, target or resource inputs run again. Logs retain failures and fresh-directory retries. Final merged application sources are also tested as an integration.

CI now uses the shared-core runner for the same default Swift/C list. Results distinguish exercised passes, explicit private-fixture skips (`passed: null`) and failures; compile errors/crashes/timeouts fail and retain partial JSON. See `CI-PROCESS-AUDIT.md` for coverage, runtime evidence and unchanged required gates.
