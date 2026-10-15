# External sound and app support

Implemented in `ExternalSound.swift`, `ExternalInstruments.swift`, and `ExternalMIDIOutput.swift`.

- SF2 and DLS via Apple sampler, with selectable zero-based program/bank values in the persisted descriptor.
- WAV, AIFF/AIF, and CAF via Apple sampler. Plain files become a chromatic instrument rooted at MIDI 60; mapping is explicitly normalized because Apple's filename-based default created one-note zones during testing. Files retain their own length and loop behavior; this does not manufacture seamless loops.
- Apple sampler `.aupreset`: importer validates `aumu/samp/appl`, reads only `file-references`, copies referenced WAV/AIFF/CAF from the explicitly selected sample directory, and rewrites references into managed storage. It rejects missing references, symlinks escaping the selected directory, other AU types, and unrelated file formats. Select a sample root with `importPreset(_:sampleRoot:)` for displaced sample trees. Only direct referenced paths, root-relative paths, and exact basename fallback are attempted; there is no disk search.
- Installed Audio Unit MIDI instruments discovered by registered component identity and asynchronously instantiated. Apple bridges AUv2/AUv3 on macOS; iOS requires installed compatible AUv3 extensions. The instantiated unit is available to the host for `requestViewController` and parameter controls. Component installations are device-specific.
- External MIDI output lists hardware and virtual app destinations by persistent CoreMIDI unique ID, and reports disconnected destinations as errors. MIDI output does not carry returning audio.
- Per-module gain/pan, low-pass filter, eight-band EQ, native dynamics processor, note tracking, sustain, panic, and binary property-list AU state APIs.

No VST/VST3, Kontakt-format import, external-app audio capture, or arbitrary AU preset import is claimed. VST3 requires a separate Steinberg hosting implementation; external apps can expose AU instruments or receive MIDI and route their own audio. No Sunday Keys assets are bundled or copied by this implementation.

## Host integration

Create one `ExternalInstrumentRack(engine:)` with the existing audio engine on the main thread. Persist `ExternalSound?` per layer; save `stateData(channel:)` after plug-in editing and restore after successful `load`. Imported library files must accompany exported sets if portability is desired. The sound descriptor alone is not a portable library export.

`load(_:channel:completion:)` completes on main and reports errors. Imports and loading may allocate/read files and are not render-thread operations. Graph edits stop/restart the engine and silence held external notes. Use `contains` to choose external versus built-in synth routing. Dispatch noteOn with both raw key and transposed pitch; use channel-scoped noteOff for MIDI effect release. Update volume/pan and processing on fader/settings changes and reapply after each load. Sustain blocking is supplied by the host by withholding sustain for blocked channels. Root UI must surface load/start errors and require re-selection for missing installations/files.

`processing` accepts linear sampler gain, fader-interpolated cutoff, resonance, EQ band tuples, compressor enabled/threshold/attack/release/makeup. Apple's dynamics processor has a different compression curve; UI ratio is not currently mapped. Imported instrument envelopes/polyphony and three custom synth effects are not controlled by this helper; AU editors own those parameters. Do not describe these as working identically to built-in channels.

## Verification

Standalone macOS and arm64 iOS Simulator 16.0 typechecking pass. A generated, user-owned WAV renders nonzero audio at middle C through the complete graph. A generated Apple sampler preset successfully copies/relinks its referenced WAV into managed storage and renders nonzero audio in a fresh offline engine. Note off, sustain, panic, removal, and installed AU discovery execute without failure. Four registered instrument components were discovered on this machine.

Third-party plug-in audio/editor behavior, real hardware MIDI output, SF2/DLS playback fixtures, and physical iPhone/iPad runtime are still unverified. Offline CLI audio tests require access to the system AudioComponent service outside the filesystem sandbox.

Apple API references: [soundbank loading](https://developer.apple.com/documentation/avfaudio/avaudiounitsampler/loadsoundbankinstrument(at:program:bankmsb:banklsb:)), [audio file zones](https://developer.apple.com/documentation/avfaudio/avaudiounitsampler/loadaudiofiles(at:)), [instrument presets](https://developer.apple.com/documentation/avfaudio/avaudiounitsampler/loadinstrument(at:)), [asynchronous AU instantiation](https://developer.apple.com/documentation/avfaudio/avaudiounit/instantiate(with:options:completionhandler:)).
