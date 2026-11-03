# Hosted macOS runner capacity follow-up

3 November 2026. PR #135's first run waited without acquiring any runners. A single retry completed the Mac artifact and processing jobs, but its Simulator/library jobs were cancelled before execution. GitHub's annotations state:

> The job was not acquired by Runner of type hosted even after multiple attempts

> Due to capacity constraints, jobs targeting macOS arm64 runners may experience longer queue times.

Run: https://github.com/WorshipWarehouse/StageKeys/actions/runs/41663622066 (attempt 2). These are infrastructure acquisition failures, not failed app/compiler/test assertions. Local full native arm64 tests and both artifact gates passed on the corresponding app source; this does not waive required hosted checks.

The workflow pins the three required job definitions to `macos-15-intel`, a supported standard Intel label in [GitHub's runner documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job). The floating `macos-15` label currently selects arm64. Pinning avoids depending on that alias's changing architecture. Availability is still subject to GitHub capacity; the label does not guarantee immediate scheduling.

The four check names, triggers, concurrency policy, commands, test inventory, timeouts and artifact validations remain unchanged. The Mac build still compiles/verifies arm64 and x86_64 slices. Hosted test and sanitizer execution now runs natively on Intel; compilation of an arm64 slice is not native arm64 execution. Native Apple Silicon runtime tests and physical stage-rig qualification remain separate, recorded gates. This PR's complete local 107 reported passes/11 explicit skips and both artifact gates ran on the arm64 Mac, with the known absent private-piano fixture caveat. The first target is the owner's Mac with AudioBox USB 96 and USB MIDI; actual latency, reconnect and soak remain open.

## Filesystem-identity test portability

The first Intel run completed both artifact gates and processing. Its library run reached MainStagePreflightTests, where a directory bookmark URL was compared directly with an input URL created before the directory existed. URL directory/trailing-slash representation is not filesystem identity. The regression now compares canonical filesystem paths, reads unique original marker bytes through the remembered grant before/after Store recreation, and regrants the same directory using an explicit directory URL to assert exactly one remembered entry. The focused program passes on the native arm64 Mac. No production import/bookmark behavior or acceptance criterion was removed; actual lost grants or unreadable content still fail explicitly.
