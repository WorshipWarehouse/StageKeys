# Actual mixed-output metering

Refs #3. Audio Settings reads sample peak/RMS from the protected output node, after the main mix, limiter and explicit headroom. Counters retain samples at/above full scale and non-finite samples for the current engine instance. The recorder and meter share one tap; metering stays available after stopping a recording. No signal normalization, gain riding or source compensation is added.

The C meter allocates once outside rendering. Its processing uses lock-free atomics, bounded per-sample arithmetic and no file I/O, locks or audio mutation. Independent fields are approximate current-block observations, not an atomic measurement transaction. Tap delivery is asynchronous; UI polling does not establish callback latency or underrun counts. These are sample peaks, not oversampled true peaks. Apple's Peak Limiter exposes attack, decay and pregain but no reduction readout; StageKeys does not fabricate gain-reduction values.

Meter tests use original synthetic buffers and the actual mixed-output tap. Maximum-polyphony/layered-instrument headroom, physical device recovery, note ownership and the full plugin/sustain matrix remain release gates. The meter reveals overload; it does not prove every possible stack is safe.
