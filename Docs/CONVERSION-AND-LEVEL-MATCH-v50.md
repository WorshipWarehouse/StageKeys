# Native conversion and output matching — 0.50

## In-app MainStage conversion

Import Sounds → Convert a MainStage Patch retains the source documents and scans the retained package for exact referenced EXS filenames. Included instruments are converted automatically using the existing native sampler/processing translator. If instruments or samples are external, the Locate/Import MainStage Sounds folder flow remains available. Unsupported synth engines, routing and processors remain in conversion notes; this is not an all-MainStage compatibility claim.

Bundled CAF/WAV/AIFF/FLAC assets now use file copies and streamed hashes instead of the 16 MB serialized-document reader. The source and copied sample hashes must agree, including a second source hash after copying. Document bounds stay at 16 MB per file / 128 MB total; bundled audio has a separate 2 GB file / 4 GB total bound. Symlink/path and 4096-entry protections remain. Failed retention removes the partial archive.

A private test runs the actual Store import on the retained Steinway reference with its original 175 MB consolidated sample, verifies native response v6 and retained rack settings, compares the managed sample hash and verifies duplicate-aware reimport. No MainStage launch, recording or resampling is involved. Large synthetic source retention and unsafe-path tests also pass. Bulk transactions, channel selection, missing-content UX and other engines remain tracked in issues #5–8.

The Update Converted Sampler Playback button now correctly includes versions below v6; it previously stopped at v5 and could hide the response upgrade.

## Optional output level matching

Sound Settings → Settings → Output Level Match measures an isolated copy of the sound. The live graph receives no probe notes. Three in-range octave-spaced pitches (or the range midpoint) are tested at velocity 83, followed by a sustained maximum-velocity chord. The layer's current effects, native sampler, host curve and plugin state are retained; the probe uses unity fader, no existing output trim, no global Space, unity master and the existing 1 dB protected output headroom. The peak limiter is bypassed only in this isolated measurement graph.

The proposal targets −24 dBFS stereo RMS in defined note windows, limited by a −9 dBFS measured sample-peak ceiling and a −24…+12 dB trim range. Quiet/invalid/unsupported output is rejected. Long attacks, key switches, tempo-driven instruments, velocity splits and the user's full repertoire require listening checks. This is fixed-probe RMS matching, not LUFS/true-peak analysis, a guaranteed safe full performance level, or equal perceived loudness for every instrument. The built-in synth's existing final soft saturation also limits exact linear prediction at high levels.

Apply writes an optional post-effects channel output trim; it does not rewrite source gain, velocity curves, samples, rack parameters or performance faders. Confirm saves the draft; Discard restores it; Reset Trim returns to unity. A changed sound/modulation cancels stale results, and closing the view cancels the isolated job. AU instantiation has a bounded readiness wait; this does not provide process isolation from a plugin that blocks inside its own code. Ten-second load timeouts and cancellation do not certify arbitrary third-party plugin behavior.

Tests cover legacy settings without a trim, invalid/silent signals, bounded peak-limited proposals, fader/trim-independent probes and post-nonlinear-effect trim at low levels. Actual Apple DLSMusicDevice and the converted native Steinway are measured; the original preset remains byte-identical. General AU/physical iOS qualification and reference-based/perceived loudness matching remain issue #25.

## Reference UI and effects

A live Sunday Keys wheel check showed held-position relative dragging and ridge lighting revealed from the bottom upward. The wheel renderer now follows that lighting progression rather than brightening every ridge uniformly. The initial low position was restored, and no MIDI calibration notes were sent.

The live SolaVerb editor confirmed Settings (Predelay/Size/Reflectivity), Character (Quality/Low Cut/Tone), Modulation (Pitch Mod/Chorus AMT/Chorus Rate), separate Dry/Wet, Effect ON/Effect Bypassed and Confirm/Discard. StageKeys now includes the previously missing Quality control, inline knob labels and the observed grouping/names. Quality reduces only the wet clock; the dry path stays full-rate and unchanged. Existing ten-parameter SolaVerb presets expand to full Quality, retaining previous indices and response. This independent stepped-rate implementation is not a measured match of Sunday's Quality taper. Tone stays in Hz until its percentage taper is measured.

Sanitizer regressions cover Sola/Shimmer Quality, dry identity, independent mixes, tails, stereo, predelay, aliases, octave tuning, maximum feedback and Panic. Existing Steinway response v6 and Shimmer damping remain intact. MainStage's saved SilverVerb comparison remains documented in Calibrations/SilverVerb-Decay-Candidates-v49.json; no new exact reverb or Shimmer sonic-parity claim is made here.

All remaining release gates are indexed in [RELEASE-ISSUES.md](RELEASE-ISSUES.md).

Live verification: the installed 0.50.0 (54) AU editor measured DLSMusicDevice, proposed a peak-limited +1.1 dB trim, applied it to the draft and restored it through Discard. SolaVerb showed the new control and inline panels; numeric Quality 100→25 worked and Discard restored the empty slot. The performance wheel held 53/127 after release and was restored to 0. The saved setlist compared equal before/after these checks. Both Mac architectures and the iOS Simulator target compile; physical iOS runtime and broad third-party AU qualification remain open.
