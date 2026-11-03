# Hosted macOS runner capacity follow-up

3 November 2026. PR #135's first run waited without acquiring any runners. A single retry completed the Mac artifact and processing jobs, but its Simulator/library jobs were cancelled before execution. GitHub's annotations state:

> The job was not acquired by Runner of type hosted even after multiple attempts

> Due to capacity constraints, jobs targeting macOS arm64 runners may experience longer queue times.

Run: https://github.com/WorshipWarehouse/StageKeys/actions/runs/41663622066 (attempt 2). These are infrastructure acquisition failures, not failed app/compiler/test assertions. Local full native arm64 tests and both artifact gates passed on the corresponding app source; this does not waive required hosted checks.

The workflow pins the three required job definitions to `macos-15-intel`, a supported standard Intel label in [GitHub's runner documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job). The floating `macos-15` label currently selects arm64. Pinning avoids depending on that alias's changing architecture. Availability is still subject to GitHub capacity; the label does not guarantee immediate scheduling.

The four check names, triggers, concurrency policy, commands, test inventory, timeouts and artifact validations remain unchanged. The Mac build still compiles/verifies arm64 and x86_64 slices. Hosted test and sanitizer execution now runs natively on Intel; compilation of an arm64 slice is not native arm64 execution. Native Apple Silicon runtime tests and physical stage-rig qualification remain separate, recorded gates. This PR's complete local 107 reported passes/11 explicit skips and both artifact gates ran on the arm64 Mac, with the known absent private-piano fixture caveat. The first target is the owner's Mac with AudioBox USB 96 and USB MIDI; actual latency, reconnect and soak remain open.

## Bookmark test executable identity

The first Intel run exposed a failing MainStagePreflightTests bookmark assertion. Stronger canonical-path, readable-marker, duplicate-grant and reload assertions ruled out URL representation as the cause: the next run reported Cocoa error 256 while creating the grant.

A local x86_64 Foundation-only A/B reproducer under Rosetta established the cause. The unsigned helper (`-Xlinker -no_adhoc_codesign`) reported `BOOKMARK_FAILED NSCocoaErrorDomain 256`; identical code linked with `-Xlinker -adhoc_codesign` reported `BOOKMARK_OK true true`. Security-scoped bookmarks need executable identity. The arm64 linker supplies ad-hoc identity by default; the Intel linker does not.

Both library test runners now explicitly request linker-generated ad-hoc identity for their ephemeral Swift test executables. This uses no developer certificate, key or entitlements and does not change app signing, release artifacts or production bookmark security. The strengthened preflight regression passes through the updated runner on native arm64. The final hosted Intel library check remains required. Running Python under Rosetta alone still selected an arm64 Swift target locally; it is not recorded as Intel suite coverage.
