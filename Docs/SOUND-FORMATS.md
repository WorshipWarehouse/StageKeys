# Sunday Keys sound formats

Inspected October 13, 2026. Read-only scope: the supplied Sunday Keys 2.5.2 app's Resources and its own sandbox `Data/Documents/Audio` directory. No sample payloads were copied, converted, played, or added to StageKeys. Account, analytics, and user database contents were not read.

## Direct findings

| Location | Actual files, excluding AppleDouble sidecars |
| --- | --- |
| App Resources | 3 `.aupreset`, 45 `.caf`, 1 `.wav` |
| Downloaded Audio directory | 21 `.aupreset`, 681 `.caf`, 216 `.wav`, 7 extensionless files |

Every one of the 24 parseable presets is an Apple property list with Audio Unit identity `type=1635085685` (`aumu`), `subtype=1935764848` (`samp`), `manufacturer=1634758764` (`appl`). This is the Apple sampler component identity. All downloaded presets specify a voice count of 64; the bundled first tonic preset specifies 12. Those stored values do not establish actual runtime polyphony.

The preset structure includes `Instrument`, `file-references`, coarse/fine tune, gain, pan, output, and opaque `data`. A downloaded Flute Organ Pad preset has an `Instrument` with LFOs, Layers, name, and voice count. Its first layer exposes Amplifier, Connections, Envelopes, Filters, ID, LFOs, Oscillator, Zones, gain, and name. Its 31 sample references point into `/EXS Factory Samples/SundayKeys/.../*.caf`. The bundled first tonic preset similarly references 12 CAF files. These are multi-zone sampler instrument presets, rather than a single rendered sound file.

The directory name `EXS Factory Samples` is present, but no `.exs` file was found in these two audio resource trees. Directory naming alone does not establish EXS24 compatibility.

Apple `afinfo` inspected representative containers:

| Example | Container and encoding |
| --- | --- |
| Bundled Classic Looped tonic | CAF; Apple Lossless (ALAC), stereo, 44.1 kHz, 16-bit source |
| Downloaded Retro Bell sample | CAF; linear PCM, stereo, 44.1 kHz, signed 16-bit big-endian |
| Bundled Legacy Foundation pad | WAV; stereo, 44.1 kHz, interleaved Int16 PCM |
| Downloaded Una Corda Felt sample | WAV; stereo, 44.1 kHz, interleaved Int16 PCM |

CAF is a container: supporting PCM CAF alone would miss the observed ALAC tonic. These four examples do not prove that every sample uses the same rate, bit depth, or encoding.

## Implications for StageKeys

Implement user-selected audio import through AVAudioFile for WAV/AIFF/CAF and sampler preset loading through AVAudioUnitSampler for compatible user-owned `.aupreset` resources. A multi-zone preset also needs its associated sample tree. Moving a preset alone does not move its sound. Resolve relative/sample-root paths safely, report missing files, and preserve imported source locations through sandbox access bookmarks where applicable.

Audio Unit instrument hosting is separate from sample import. Discover installed `aumu` components, instantiate AVAudioUnit instances, route MIDI and per-channel audio, expose the plugin editor where available, and persist plugin state. MIDI output to external apps/hardware is another separate route. A VST/VST3 binary cannot be loaded through AVAudioUnit; it requires a dedicated host implementation and SDK integration. Do not advertise VST support merely because external MIDI or AU works.

The observed sample files are technically ordinary Apple-compatible resources; their presence is not a license to redistribute them. StageKeys should use user-selected, authorized libraries and independently created defaults.

## Evidence and limitations

`work/evidence/sunday-sound-formats.json` records exact bounded roots, inventories, preset SHA-256 hashes, component IDs, top-level schema keys, three example references per preset, and representative `afinfo` output. `work/evidence/inspect_sound_formats.py` is the reproducible read-only inventory script. The previous REA artifact record (`outputs/SundayKeys-Analysis/evidence/artifact.json`, Evidence `ev_2bdbe247184e60ec12c8d1083c55b3196801dceca12c72fc9e19383bbc7aee75`) independently establishes bundled resources. Current downloaded sound inspection uses Python plist parsing and Apple's afinfo, not a new REA record.

No entitlement-restricted downloads, private server protocols, decryption, Realm content, source recovery, or runtime sampler call tracing were attempted. The actual licensed full library, supported third-party preset variants, and Sunday Keys' path remapping algorithm remain unverified.
