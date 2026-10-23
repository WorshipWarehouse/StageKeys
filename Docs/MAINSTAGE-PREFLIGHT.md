# Review before native conversion

Refs #5. Choosing a MainStage patch/CST retains the original source and displays its report without adding playable sounds. Select the sampler channels in the report, then choose **Convert Included Instruments** or **Locate Samples and Convert Selected Channels**. Empty/out-of-range selections cannot enter conversion. The explicit step keeps preflight distinct from library mutation and preserves channel order.

The converter still validates exact retained source hashes and refuses ambiguous instrument matches. It preserves original samples without rendering or opening MainStage. Processing notes identify partial translations; a referenced EXS alone does not prove complete native fidelity. Concert traversal, comprehensive missing-content repair after relocation, and a fully transactional bulk importer remain separate release work.
