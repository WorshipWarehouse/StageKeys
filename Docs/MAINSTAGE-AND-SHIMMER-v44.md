# MainStage conversion and Shimmer — 0.44

## Additional playable channels

The optional private pack now contains 12 channels, up from nine: Flute Pad, Kid Pad and Power of Love · Power of Love 2 are new. The 167 referenced sample copies match SHA-256 hashes of original audio files identified in the retained EXS sample tables. Original EXS and source patches remain byte-for-byte preserved. No MainStage process, replacement recording or resampling is used. Each new channel retains supported source processing; Flute Pad includes EQ, compressor, SilverVerb and stereo delay. Power of Love 2 remains a single channel of a layered patch whose other instruments are not converted. Space Designer and other unsupported processing remain explicitly reported.

All 12 pack channels passed 48 renders at velocities 38, 83, 102 and 127, with no silent channels or reported audio errors. Their serialized rack state matches a fresh translation of their retained source channel documents. The complete archive audit still covers 358 patches and 427 channels; twelve channel occurrences now have native entries and four patches have complete channel coverage. This does not establish full patch routing or DSP parity. Non-sampler engines and absent original instruments remain conversion blockers.

## EXS record layout

The bounded reader now handles the flagged 15-bit short size used by the 0x80 header family while preserving ordinary 32-bit chunk lengths. Some legacy factory documents use record-order sample references even when all sample header IDs are zero, and their group header IDs may contain gaps. Legacy ordinal references are normalized only when every referenced record belongs to the legacy family and the zone references fit the record table. Modern explicit IDs remain unchanged; invalid/mixed references still fail validation. Synthetic tests cover duplicate legacy sample headers, sparse legacy group headers, modern identity preservation, encoded/ordinary size equivalence and truncated records.

The size encoding was cross-checked against the [MIT EXS layout reference](https://github.com/matt-allan/renoise-exs24/blob/main/exs.lua), in addition to the installed original files. No third-party parser is bundled. The recovered instruments currently use Apple's public sampler's compatible importer where supported; the independent reader remains the fallback for rejected documents.

## MainStage controller defaults and Steinway

New MainStage rack metadata retains unity volume/expression initialization. It covers ordinary system-loaded sampler instruments as well as the previously supported modern EXS conversions. CC7/CC11 initialize to 127 only when no actual value has been received; reconfiguration and Panic preserve received volume. A generated-sample regression measures a 1.6129 amplitude ratio (about 4.15 dB) against the sampler's default CC7=100, with identical source bytes. Explicit received CC7=100 remains unchanged.

This corrects a general import-level issue; it is not a new calibration of the Steinway's baseline amplitude law. The existing measured -10 host-curve adjustment remains unchanged. A new live capture was attempted but MainStage's output was muted and its workspace output control did not accept a verifiable adjustment. Its original piano/output muted state and tuner-off state were restored; no new recording or level comparison is claimed. The saved references remain available. Exact Steinway baseline velocity/loudness and source effect equivalence remain open.

## Shimmer octave-path alias suppression

Before octave-up shifting, the wet pitch history now passes through two cascaded low-pass biquads. The cutoff respects half the requested output Tone and the reduced Quality processing rate. This reduces high harmonics folding back into the audible range during the pitch shift and recirculation. The original direct signal and the unshifted room branch are unchanged. There is no added dry-path latency or source sample edit.

At 44.1/48/96 kHz, generated high-frequency probes produce much less wet energy than the lower-frequency reference (ratios 0.001838/0.000163/0.000001 respectively). Quality, dry identity, independent mixing, octave-band content, dense tails, maximum feedback, stereo decorrelation and Panic regressions pass. These checks establish alias attenuation and bounded operation, not Sunday Keys' exact algorithm. Grain sidebands, exact Tone taper, modulation/diffusion and subjective source matching still need comparison.

## Release checks

Universal macOS and iPhone/iPad simulator Release builds pass. Legacy identity/size, MainStage controller-default and processing persistence tests pass. The private Steinway measured host-gain regression and 15-second D5/upper-octave held-note regression pass, preserving sample references and excluding a late neighboring-note attack. The optional pack verifies 239 file hashes and contains no personal plugin state. Physical iOS listening and exact source-effect listening comparisons remain outstanding.
