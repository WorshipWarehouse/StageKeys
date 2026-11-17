# StageKeys Sampler and MainStage documents

StageKeys Sampler is an in-app instrument interface using Apple's system AVAudioUnitSampler, not MainStage's private Sampler plug-in. It exposes the imported sample map: sample/layer/zone counts, root keys, key ranges, velocity ranges and loop status. Existing sampler gain, channel pan and translated processing controls remain available. The map is read-only; this release does not claim a new sample-editing engine.

New EXS/AUPRESET sound-file imports retain an exact original instrument in the personal `Original Instruments` directory, identified by SHA-256. The managed playback preset still relocates samples through the existing importer. Samples are copied, never rendered or resampled. Original EXS retention preserves fields which Apple's loader might not expose; this is not a guarantee that Apple's standalone sampler reproduces all EXS features.

## Effect selection and instrument controls

A converted channel no longer appends every translated processor to an imported rack. The import report exposes a **Choose Effects** sheet for each selectable channel. It lists the translated source effects in source order, with the source device name, enabled/bypassed state and the compatibility notes recorded during translation.

- Channel EQ maps automatically to the instrument's FX A equalizer, and the Compressor maps automatically to FX B. Filter slopes, output gain, circuit model, knee, sidechain and exact Apple response remain approximate.
- At most three other source effects can be selected for the three visible audio slots. Empty slots are not filled automatically, and no overflow rack is created. A source effect that is not selected stays in the archived channel strip and in the data-only source record on the converted layer.
- The source MIDI transform is retained but has no verified native translation. The sheet allows a manual native MIDI effect for the visible MIDI slot and labels it as a replacement, not a translation. Verified linear Smart Control assignments targeting selected native audio effects are active; unselected, nonlinear, instrument, and unsupported targets remain source data only.
- Original patch/CST bytes, sample bytes, hashes and conversion IDs are unchanged. Omitted effects, additional EQs/compressors and unsupported parallel/send topology are reported in the conversion notes.

The selection is part of the converted layer and survives JSON/library persistence. Legacy layers without a source record still decode, and an existing imported rack is preserved rather than replaced.

## MainStage import status

Import Sounds → Import a MainStage Patch reads `.patch/data.plist` and referenced `.cst` documents without opening MainStage or loading source plug-ins. It identifies observed legacy device records, EXS filenames, macro mapping records and MIDI-transform presence. The source bundle is copied byte-for-byte into personal `MainStage Sources`, with source hashes and a conversion report. Unknown effects, routing, macros, MIDI state and script records are retained as opaque document data, never executed. The latest report survives app restart.

**This is a lossless source importer with bounded playable conversion, not a complete MainStage runtime.** A supported sampler channel becomes playable only after its original sample dependencies pass preflight. The chosen native effects, instrument EQ/compressor, supported channel settings, source velocity curve, and verified linear mappings are saved with that sound. Omitted processors and unsupported topology remain in the archived source record and conversion notes; they are never silently flattened or substituted. An EXS filename alone does not establish a faithful patch conversion. No workflow launches MainStage or invokes Auto Sampler.

The local read-only audit found 358 patch folders and 427 channel strips; 66 channel strips referenced EXS. Other observed instruments include ES2, Retro Synth and Sculpture. Sampler support cannot reproduce those synthesizers by itself. One source patch lacked a supported channel list and was reported rather than guessed. This inventory is evidence from the user's local archive, not a bundled catalog.

## Verification and limits

Generated fixtures cover bounded device parsing, sampler-reference detection, macro/MIDI data retention, exact-byte source archiving, refusal to overwrite archives, invalid headers, traversal rejection, sample-map fields and original-instrument hashing. Existing library/rack regressions continue to run. Mac and iPhone/iPad builds are required.

Modern/consolidated EXS files that Apple's system sampler rejects are decoded into the native StageKeys sampler format when all used group, zone, envelope, loop, and sample-reference features are supported. Unsupported selection behavior, routing, tails, tuning, or envelope layouts fail explicitly; the importer does not flatten the map, fabricate a piano, or fall back to a sine wave. The original source file and sample bytes are never changed.

Remaining implementation work:

- Decode the remaining sampler front-panel overrides and EXS group/parameter behaviors that currently fail explicitly.
- Translate the processors that remain archive-only (additional EQs, source MIDI FX, filters and unsupported parallel/send topology).
- Decode source MIDI FX, filters, nonlinear Smart Control curves, and targets outside selected native audio slots.
- Supply native equivalents for private synthesizers where possible, with explicit fidelity limits.
- Validate complete translated patches against reference behavior before declaring them playable conversions.

The source format does not supply a public standalone MainStage runtime. Porting or translating document data is a separate task from wrapping the system sampler.
