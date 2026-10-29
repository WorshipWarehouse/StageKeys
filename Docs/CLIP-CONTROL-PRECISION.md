# ClipDist control convergence

The 20 ms gain/mix one-pole smoothing state used float precision. Near its target, an update could round to zero, leaving persistent control error (about 4.1e-5 relative residual in the original imported-effect regression). This was not entirely the intended automation ramp.

Only the three private ClipDist control accumulators now use double precision. Targets, audio buffers and public parameters remain floats; preset formats are unchanged. The smoothing coefficient and 20 ms response are retained. This adds 12 bytes of accumulator payload per effect state (structure alignment may add padding), with no allocations or locks in rendering.

MainStageEffectAudioTests retains its original absolute settled-gain error threshold of 0.01 after a one-second settling window. Predelay, proportional transient, density, symmetry, finite-output and Panic assertions remain. It now runs in the ASan/UBSan processing gate.

ClipDistAutomationTests retains the initial ramp assertion and tightens settled output gain to 1e-6 at 44.1/48/96 kHz, with a 200×256-frame window so even 96 kHz has more than 26 time constants. The old float implementation fails this tightened regression; the new implementation passes all three rates. The full reverb/effect sanitizer suite passes. This is independent DSP control accuracy, not a claim of proprietary effect parity or a physical CPU benchmark.
