# Native MainStage compatibility — matrix version 1

Refs #7. The app imports documents independently; it never launches MainStage, resamples audio, runs archived scripts or ships Apple's private instruments. A sampler candidate is not a declaration of full patch fidelity.

| Source | Native status | Unsupported behavior |
| --- | --- | --- |
| Legacy/modern EXS with verified records | Convert original sample maps to StageKeys Sampler | Reject invalid identities, unsupported active group selection/crossfades/release triggers, reverse/unpitched/routed zones and unrecognized global envelope layouts |
| Sampler AUPRESET with portable original sample references | Managed sampler import | Missing samples and unverified private instrument state must be repaired or rejected |
| ES2 | Archive only | No native synthesis engine |
| Retro Synth | Archive only | No native synthesis engine |
| Sculpture | Archive only | No physical-model engine |
| Alchemy | Archive only | No proprietary engine/container reader |
| Third-party instrument | Installed compatible AU hosting | License/content/platform dependency remains; no container extraction |
| Unknown device | Retain source and report processing limitations | Never infer success from a similar name |

The conversion report shows instrument status per channel. Known unsupported synth devices cannot enter the native sampler conversion path even if unrelated EXS filenames also occur in their documents. An unrecognized global EXS envelope no longer receives an arbitrary fallback that changes the sound. Source files remain intact.

Known translated processors and approximations are documented in the processing reports and versioned effect docs. Send/return topology, script execution and all source modulation behaviors are not fully supported. New variants require original/synthetic fixtures, active playback tests and source comparison before this matrix can expand. Supported-file conversion is not a blanket all-MainStage promise.
