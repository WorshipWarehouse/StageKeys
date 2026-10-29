# Native MainStage channel fader translation

Refs #6 and #25. Observed on macOS with MainStage **4.3.1** on 2026-10-29. This qualifies the saved channel fader mapping, not overall instrument/effect loudness parity.

## Reference procedure and observations

Opened the existing user-authorized Steinway calibration concert, copied its document to `/private/tmp/StageKeys Fader Calibration.concert`, and opened that disposable copy in MainStage. Selected **Steinway Reference / Grand Piano**, moved the channel mixer fader, read its displayed dB value, used File → Save, and read only the corresponding channel's `volume` in the saved patch `data.plist`. No sample bytes or proprietary preset payloads are included here. The original concert was not saved or modified. No audio capture, MIDI stimulus, sample-rate or block-size comparison was used for this serialized-control measurement.

| Mixer display (dB) | Saved channel `volume` |
| --- | ---: |
| −∞ (Sum channel) | 0 |
| −52.0 | 75676738 |
| −18.0 | 535750245 |
| −6.0 | 1070042940 |
| 0.0 (Pad channel) | 1509949440 |
| +5.9 | 2120617814 |
| +6.0 (maximum position) | 2130706432 |

Inference supported by these independent saved observations: the serialized value is Q24 square-root amplitude with unity at 90 and maximum at 127. For a supported finite integral value `raw`, `amplitude = (raw / 1509949440)^2`; zero is exact silence. The −18, −52 and +5.9 dB points match within 0.000002 dB. Display rounding explains the −6.0 point (−5.982448 dB) and maximum (+5.982448 dB). The accessible mixer slider's positional value is a different scale and must not be used as the serialized value. Other MainStage versions/encodings remain unqualified.

## Integration and limits

Both native sampler and hosted-AU import use the same processing draft. Previously only silence and unity were decoded; other saved values emitted a warning and left a new layer at unity. Now supported attenuation sets the layer fader, while boosts keep that fader at unity and add their dB value to the existing post-effect Output Trim. This respects the persisted 0–1 fader range and avoids changing a compressor/distortion's input drive. A combined trim outside the existing −24…+12 dB bounds fails explicitly; it is never clamped silently. Users see the source fader and boost placement in the processing preview.

Malformed, fractional, boolean, negative, non-finite or above-maximum encodings remain untranslated with an actionable warning; absent fader metadata leaves the destination unchanged. Original archived documents, sample bytes, plug-in state, effect order and controller behavior are unaffected. This does not translate parent buses, sends, output/master gains, expression response or unsupported processors. It does not automatically rewrite previously imported user patches. Conversion identity now includes the original patch metadata digest and channel filename as well as the CST/instrument identity: changing only a fader creates a new converted sound rather than skipping it as a duplicate. Unchanged reimport reuses the existing sound, preserves user edits, and associates it with the new retained source archive so patch assembly still works. Older conversion IDs remain intact; their first conversion under the new format adds a fresh version. Reimport into a new destination or apply the reviewed source processing to a draft.

## Regression checks

`MainStageFaderTests` uses the measured numerical values, checks malformed inputs and gain bounds, round-trips layer settings, and renders an original generated sample through the production sampler/effect/output path to check silence, −18 dB attenuation and positive boost. `MainStageAudioUnitImportTests` verifies the −18 dB setting through import, library reload and assembled-patch creation without requiring a third-party binary. Test audio is generated locally and never bundled.
