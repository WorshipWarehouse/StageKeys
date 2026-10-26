# Transactional catalog import

Refs #8. Native MainStage channels, sampler folders and separate library packs now prepare entries without saving the catalog per item. An error or cancellation before commit leaves catalog bytes unchanged. Commit compares the current catalog to the captured version and refuses to replace intervening user edits. Stable source-derived IDs retain duplicate-aware retry; existing personal entries are skipped rather than replaced.

Sampler-folder conversion yields between instruments and supports **Cancel Import Before Commit**. Cancellation waits for the current synchronous instrument operation to return; no partially converted catalog entry is published. This is not instantaneous interruption of an Apple audio-unit loader. Source samples are unchanged. Managed presets/sample copies prepared before cancellation can remain unreferenced on disk; this PR does not delete potentially shared assets. Disk staging/garbage collection and resumable checkpoints are remaining work.

`TransactionalImportTests` verifies concurrent-edit refusal, duplicate refusal, successful single commit, actual Store cancellation and malformed-source failure using disposable data. Clean-machine playback without MainStage, relocated-library recovery and the legally usable full golden corpus remain release qualification; passing the catalog test does not establish them.
