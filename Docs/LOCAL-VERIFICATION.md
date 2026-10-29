# Local release verification

Run the existing Swift test list with a single testable core module:

```
python3 Tests/run-local-library.py . /private/tmp/stagekeys-local-tests
```

An optional trailing list selects tests. The runner reads the same Sources and default test list as `Tests/test-library.sh`, compiles the complete core once with DEBUG/testable access, then compiles and executes each unchanged test body against it. Every run uses a fresh private data directory; no user session, source library or original samples are overwritten. This changes test build organization, not test assertions. The original shell runner remains available for monolithic builds and private fixture arguments.

The default list also covers the native C DSP regressions (`AudioEffectsTests`, `ChannelDSPTests`, `ChannelPanicTests`, `RackTests`, `SynthTests`), which link the C objects built by the same script and need no Swift sources or audio hardware.

Three tests stay on demand. `AudioDeviceTests` and `LivePatchContentTests` need a live output device, which hosted runners provide only intermittently: the first asserts the real device inventory and buffer status, the second asserts captured audio through a running engine. `PatchGainTests` is excluded because its measurement window is not deterministic: it asserts patch gain through a streamed external sample, and the stream's onset moves. In 40 local runs it failed 3 times, and it failed once in two hosted runs of identical code, because between 17 and 25 of the 80 measured blocks carried digital silence; whenever every block carried signal the ratios were exactly 1.99526 and 0.50119. Run all three on a Mac:

```
Tests/test-library.sh AudioDeviceTests LivePatchContentTests PatchGainTests
```

`PianoHeldNoteTests` runs by default but returns immediately unless `STAGEKEYS_PIANO_PRESET` names a private Steinway preset, the same way `EXSImportTests` skips without its fixture arguments.

Release checks still include universal Mac and iOS Simulator builds, `Tests/test-reverb.sh` with ASan/UBSan, applicable Python corpus/evidence checks, and source/bundle content validation. A simulator build is not physical iPad qualification. Local checks do not alter GitHub billing or report hosted CI as green.

The PR matrix records the exact commit SHA for each revision. Completed DSP/build results may be reused only for byte-identical complete input sets; cache entries retain the originating PR/SHA and input SHA-256. Distinct code, test, target or resource inputs run again. Logs retain failures and fresh-directory retries. Final merged application sources are also tested as an integration.
