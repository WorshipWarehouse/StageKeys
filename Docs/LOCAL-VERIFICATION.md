# Local release verification

Run the existing Swift test list with a single testable core module:

```
python3 Tests/run-local-library.py . /private/tmp/stagekeys-local-tests
```

An optional trailing list selects tests. The runner reads the same Sources and default test list as `Tests/test-library.sh`, compiles the complete core once with DEBUG/testable access, then compiles and executes each unchanged test body against it. Every run uses a fresh private data directory; no user session, source library or original samples are overwritten. This changes test build organization, not test assertions. The original shell runner remains available for monolithic builds and private fixture arguments.

The default list also covers the native C DSP regressions (`AudioEffectsTests`, `ChannelDSPTests`, `ChannelPanicTests`, `RackTests`, `SynthTests`), which link the C objects built by the same script and need no Swift sources or audio hardware. Two tests stay on demand because they need a live output device, which hosted runners provide only intermittently: `AudioDeviceTests` asserts the real device inventory and buffer status, and `LivePatchContentTests` asserts captured audio through a running engine. Run them on a Mac with an output device:

```
Tests/test-library.sh AudioDeviceTests LivePatchContentTests
```

Release checks still include universal Mac and iOS Simulator builds, `Tests/test-reverb.sh` with ASan/UBSan, applicable Python corpus/evidence checks, and source/bundle content validation. A simulator build is not physical iPad qualification. Local checks do not alter GitHub billing or report hosted CI as green.

The PR matrix records the exact commit SHA for each revision. Completed DSP/build results may be reused only for byte-identical complete input sets; cache entries retain the originating PR/SHA and input SHA-256. Distinct code, test, target or resource inputs run again. Logs retain failures and fresh-directory retries. Final merged application sources are also tested as an integration.
