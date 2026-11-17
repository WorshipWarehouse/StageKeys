# Tonic Pad library selection

Tonic Pad can use an installed StageKeys Sampler sound without copying its sample assets. The picker separates eligible looped samplers from unsupported entries and reports the eligibility reason in place.

Selection is transactional:

- opening **Choose Sound** captures the current sound, selector mode and timbre;
- choosing an eligible row auditions it through the dedicated Tonic Pad channel;
- **Use Sound** persists the preview;
- **Cancel** restores the captured sound and selector state;
- failed loads restore the previous playable sound rather than silently substituting content.

An eligible sampler must provide sustainable looped coverage for MIDI notes 36–47 at normal velocity, or use the supported twelve-velocity timbre layout. Missing files, incomplete coverage, unsupported maps and Audio Units remain visible with an explanation but cannot be selected.

## Audio Units

Audio Unit-backed Tonic Pads are intentionally disabled. Enabling them requires a separate lifecycle design and regression coverage for held-note ownership, panic, patch transitions, state restoration, replacement, loading failure and stale asynchronous callbacks. Until those guarantees exist, an AU is rejected before the current Tonic Pad is changed.
