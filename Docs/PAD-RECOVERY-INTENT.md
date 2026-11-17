# Pad intent across unexpected audio recovery

3 November 2026. Follow-up for #3, #110 and #123. This changes software recovery ownership; physical route/competing-app/unplug/sleep evidence remains required before those issues can close.

The previous startup/configuration failure cleanup called ordinary Panic, clearing the live Tonic Pad root. A successful device transaction had a separate preservation path, and graph failures also retained the pad, but an unexpected engine configuration notification did not. A generated regression failed on main with “Unexpected route failure must retain the live pad and click choices.”

Unexpected graph, engine-start and configuration recovery now share one cleanup: retain pad root/sound and click intent, clear sounding voices, held notes/pedals and pressed controller ownership, then wait for the existing bounded recovery policy. The existing successful-start path re-arms a retained pad only after the engine and patch are accepted. The pad retriggers; this does not preserve envelope phase, DSP history, click phase or uninterrupted audio. Locked patch recall still owns its documented state. Saved session/settings bytes are not rewritten by failure handling.

Manual Stop revokes pending pad resumption, invalidates retry generations and clears the live pad as before. Explicit Start on an unlocked patch cannot resurrect that cancelled pad. Ordinary note/pedal ownership remains cleared during failure rather than being replayed indiscriminately.

`AudioStartupRecoveryTests` now exercises a generated looping sampler: an injected route-stop plus three failed busy starts, retained pad/click selection with no sounding host note intent, unchanged session/settings bytes and patch/snapshot identity, actual pad audio after explicit retry, successful automatic route recovery with one owned pad note, and Stop during backoff followed by explicit Start without pad resurrection. Core Audio configuration notifications are simulated; no physical output is opened by the offline test. Existing graph-failure, manual-Stop, cancellation, Tonic and Store programs form the focused regression set.

Exact commands, outcomes and frozen input hashes are recorded in [verification](Completion/pad-recovery-intent-verification.json). Private audio/reference assets are not used. Real AudioBox/device behavior, real hosted-AU stress, hardware latency and prolonged stage rehearsal remain unqualified.

Final local verification: six focused programs passed, then the complete suite reported 107 passes, 11 explicit skips and zero failures. The known absent private-piano case remains unexercised despite its reported pass. Both unsigned Mac and Simulator artifact gates passed; all 217 frozen source/test/project/CI inputs matched after the checks.

Hosted validation follow-up: unstarted arm64 jobs were cancelled by GitHub capacity acquisition errors, so the required workflow is pinned to the documented Intel pool with unchanged commands/check names. [Runner evidence and architecture limits](CI-RUNNER-CAPACITY.md) records the runner selection and later filesystem-identity assertion follow-up. App source/project inputs remain unchanged; the original complete local suite keeps its earlier test/workflow hashes, and the new targeted bookmark check has a separate recorded outcome.
