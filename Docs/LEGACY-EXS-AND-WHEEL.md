# Legacy EXS neutral crossfades and modulation wheel — 0.46

Legacy EXS group crossfade fields at body offsets 32 and 35 may encode a zero amount as unsigned 128. The parser previously accepted only a zero byte, rejecting factory Steinway Grand Piano 2 before producing a playback map. It now also accepts 128 and continues rejecting every other amount; active crossfades are not flattened. The zero-byte encoding remains supported for existing documents.

Field reference: https://github.com/git-moss/ConvertWithMoss/blob/main/src/main/java/de/mossgrabers/convertwithmoss/format/exs/EXS24Group.java (read/write crossfade fields use a 128 bias). This is a format fact; no upstream implementation code was incorporated.

The synthetic regression converts all four combinations of zero/128 into identical native maps, rejects five nonneutral key/velocity crossfade combinations, and checks original sample bytes are unchanged. Fresh conversion of the two original Two Pianos channels preserves the original sample SHA-256 values and produces the same semantic instrument maps as the retained pack, allowing for connection order/IDs. These are recovered conversions, not two additional catalog sounds. The current source EXS and retained earlier alias differ bytewise; their resulting sample hashes and playback maps agree.

Sunday Keys wheel inspection: dragging changes its held position; tapping elsewhere does not jump to the pointer; double-clicking did not reset it. StageKeys retains that relative/held interaction. The visual update uses neutral metallic ridges and a wider wheel with a smaller gap to the keyboard. Gesture output is quantized to MIDI CC1's 127-step range and repeated identical values are suppressed. Hardware CC1 and snapshot interpolation remain supported.

Modern Steinway Piano 2 loudness/velocity calibration is still open. This parser fix does not change its amplitude response or the measured host-curve correction. Existing click, loop-region and latency repairs are retained. No new Shimmer DSP change is claimed in this release; its existing alias and tail tests remain the baseline.

Validation: macOS universal and iOS Simulator Release builds pass. The signed 0.46.0 (50) Mac app was opened and its wheel checked live: a tap preserved 0/127, a relative drag reached 62/127 and held, and a downward drag restored the original 0/127. The distribution audit confirms no sampled library assets ship inside the app. The iOS check is compilation only.

Two temporary 12-note amplitude-only render sets were also prepared with sampler filters and effects bypassed, retaining original sample files. No amplitude-law or global-gain change was promoted: MainStage reopened to the concert chooser rather than the previously calibrated reference, so there was no verified matching source capture for this experiment. The reference-only Sunday Keys Shimmer draft was discarded; its saved settings were not changed.
