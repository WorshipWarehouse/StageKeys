# StageKeys public release checklist

Updated 20 October 2026. StageKeys is a development build, not ready for a public reliability or complete MainStage-compatibility claim. This is the release gate list, not a list of completed features. Current implementation evidence lives in PARITY-STATUS.md, MAINSTAGE-NATIVE.md, REVERB-REFERENCE.md and Calibrations/. Historical version documents are not current coverage totals. Native response v6 now passes the dry Steinway calibration at three pitches and five velocities (two passes), within 0.04 dB after the intentional output headroom; this does not close the broader audio gate. See [sampler response evidence](SAMPLER-RESPONSE-v48.md).

## Product scope and release sequence

1. Finish audio correctness and reliable sample-based MainStage conversion on macOS.
2. Run a private performance beta with a defined compatibility matrix and repeatable support diagnostics.
3. Ship a macOS release only after the gates below pass. Ship iPad/iPhone when the same gates pass on physical supported devices; simulator compilation is insufficient.
4. Expand supported MainStage instrument families and plugin formats using published compatibility lists. Do not describe archived or unsupported patches as converted.
5. Build our own optional AI patch builder later. Cloud/Prime replication remains outside the requested scope.

Aim for familiar, fast performance workflows and equivalent useful behavior. Before public release, finish StageKeys' own visual identity, wording and artwork. The current comparison UI is a development reference, not a finished public design.

## P0 — audio correctness and live reliability

- [ ] Match Steinway Piano 2's amplitude/velocity law against a retained, reproducible MainStage reference: original sample/zone identity, both pedal states, low/middle/high register, velocities 1–127, isolated notes and sustained chords. Separate host velocity shaping, instrument gain, channel EQ, bus gain and effects. Provisional target: dry steady-level error within 1 dB at representative velocity points, with reviewed layer transitions; document exceptions instead of patch-specific hidden compensation.
- [ ] Keep the repaired click, streaming, loop boundaries and latency paths under regression. Hold every representative zone beyond its original sample/loop boundary; no late neighboring-note attack, discontinuity, runaway voice or truncated decay. Compare note-on timing and attack/decay/release to the source, not only RMS.
- [ ] Measure physical MIDI-to-audio latency and jitter on supported devices at available buffer sizes. Publish the tested device/buffer matrix. No unexplained extra buffering compared with the reference host.
- [ ] Prove bounded headroom for dense chords, maximum polyphony, sustain, stacked layers and reverb tails. Meter the actual output and expose limiter/gain-reduction behavior clearly; no automatic gain change that hides a conversion error.
- [ ] Stress streaming and preload: slow/external storage, missing/offline files, rapid patch changes, overlapping release tails and memory pressure. No disk reads, allocation, locks or graph rebuilds on the audio render thread.
- [ ] Verify note ownership, repeated same-pitch notes, sustain/sostenuto/half-pedal where supported, pitch bend, CC1/7/11, disconnect/reconnect and Panic across native instruments and hosted plugins.
- [ ] Pass a proposed eight-hour scripted performance soak on each supported hardware class: no crash, stuck notes, invalid output or unbounded memory/CPU growth. Record underruns and worst render duration, not just average CPU.
- [ ] Recover from audio-device unplug/replug, sample-rate/buffer changes, sleep/wake and interruption without losing the saved session. Restore audibility deliberately and display actionable failures.

## P0 — easy, honest MainStage conversion

Current private archive audit: 358 patches / 427 channels; 12 channel occurrences have retained native entries and four patches have full channel coverage. Full channel coverage is not full routing/effect fidelity. Most remaining channels require unsupported synth engines or missing original instruments. Recovered Two Pianos conversions do not add catalog sounds.

- [ ] One obvious Import Sounds entry accepts .patch/.cst/.exs, folders and supported concert assets; preflight before committing. Explain whether the import is a playable native sound, a partially translated patch, or an archive only.
- [ ] Copy or securely reference the exact original samples; preserve hashes, roots, zones, velocity ranges, tuning, start/end offsets, loops, envelopes, filters, groups and controller conditions. No resampling and no need to launch MainStage for supported files.
- [ ] Resolve missing samples/instruments with a clear Locate workflow, exact identity checks and portable managed copies. Relink after moving the library or changing computers. Do not silently substitute a similarly named instrument.
- [ ] Translate the supported channel strip's actual order, bypass states, gain/pan, EQ, compressor, delay/sync, reverb, distortion, sends/returns, bus/parallel topology and stereo routing. Retain original serialized source documents alongside normalized settings.
- [ ] Translate macros, controller ranges/inversion/curves, velocity response, note/channel routing, arpeggiators and supported MIDI scripts into active processing. Warn for every untranslated dependency.
- [ ] Publish a versioned compatibility matrix for instruments and effects. Add independent engines or explicit unsupported status for ES2, Retro Synth, Sculpture, Alchemy and other non-sampler instruments; sampler conversion alone cannot reproduce them.
- [ ] Support modern and legacy EXS variants including documented selection/crossfade/release behavior, or reject each unsupported behavior explicitly. Never flatten it silently.
- [ ] Import entire layered patches with preserved ordering and channel relationships, not only isolated playable channels. Preview what will change and let users select channels.
- [ ] Make bulk import cancellable, resumable, duplicate-aware and transactional. Failed import leaves the library unchanged; reimport supports versioning without overwriting personal edits.
- [ ] Run a representative, legally usable golden corpus on a clean Mac without MainStage installed/running. Check playback and settings after app restart and after library relocation. Private vendor fixtures stay in the separate private library repo.

## P0/P1 — effects and sound fidelity

- [ ] Finish Shimmer's octave tuning, harmonic/alias behavior, feedback stability, density, stereo image, size/diffusion/modulation and Tone/Quality tapers. A spectral test is necessary but insufficient: compare pads, piano chords and held notes against Sunday Keys at matched controls and levels.
- [ ] Match MainStage EQ and compressor behavior, including bandwidth/Q conversion, attack/release, detector/makeup/mix and bypass. Measure gain transfer and transient behavior.
- [ ] Finish SilverVerb, ClipDist, synced/stereo/tape delay and remaining source processors. Match predelay, early-reflection timing, decay versus frequency, wet/dry gain and routing; do not equate a named control with the original algorithm.
- [ ] Finish every public built-in effect's meaningful controls and presets: Tone, tremolo, delay, bitcrusher, chorus, compressor, EQ, flanger, gain, Shimmer, overdrive, pitch shift, PrimaVerb, rotor, SolaVerb and imported processors. Hide or mark any control that does not process audio.
- [ ] Match effect defaults/preset recall, enable/bypass, live previews, Confirm/Discard and snapshot updates. Verify tails on bypass/replacement and parameter automation without clicks.
- [ ] Test every processor at 44.1/48/96 kHz, mono/stereo, minimum/maximum values, long feedback, automation, block boundaries and Panic. Establish per-effect CPU and memory budgets.

## P1 — plugins and external instruments

The code has an Audio Unit instrument-hosting foundation and external MIDI support. That is not a finished plugin compatibility claim. Native effects remain the primary workflow; external effects are optional future scope rather than a dependency for MainStage conversion.

- [ ] Finish macOS Audio Unit discovery, scan/rescan, vendor/name search, validation, unavailable-plugin reporting and an instrument picker integrated with the sound library.
- [ ] Open plugin editors reliably; expose a usable generic parameter editor when no custom editor exists. Preserve plugin identity, full state, MIDI routing and automation through save/reload, duplicate, snapshot, preset and patch switch.
- [ ] Define and test hosted-plugin crash/hang isolation, loading timeouts, quarantine/skip behavior and recovery. A broken plugin must not corrupt the session or prevent the next launch.
- [ ] Validate mono/stereo/multi-output handling, sample rate/block-size changes, latency compensation, sustain and patch transitions with a published real-plugin test matrix.
- [ ] Complete AUv3 instrument hosting and editor lifecycle on physical iPad/iPhone; clearly distinguish plugin availability per device. Do not promise that a Mac plugin binary/library works on iOS.
- [ ] Decide whether direct VST3 hosting is a release requirement or later milestone. Current AU hosting does not provide VST3 support. If added, implement the host, scanning, state/editor integration and crash handling separately; publish architecture/platform support.
- [ ] Explain Kontakt and other proprietary library dependencies: host an installed compatible plugin where available; do not present their sample containers as supported native imports without a verified reader.
- [ ] Finish external MIDI destination/virtual-port setup, channel mapping, persistence, reconnect and loop prevention; test with real external apps/devices.

## P1 — complete performance and library workflows

- [ ] Verify all 15 sound slots independently: add/replace/remove/reorder, gain/pan/mute, key/velocity range, transpose, EQ, MIDI FX, three audio FX slots, imported rack processing and MIDI learn.
- [ ] Finish setlist/patch/snapshot create, recall, duplicate, rename, reorder, Trash/restore, notes, transitions and Patch Lock. Confirm tails and held notes behave predictably on patch changes and rapid recall.
- [ ] Finish Tonic Pad power independent from sound selection, per-patch lock/recall, 12 keys, brightness as tone, Shimmer, volume, modwheel response and smooth changes without retriggering.
- [ ] Finish library names, trustworthy source/inferred tags, Note Range/Complexity filters, Recommended/rating/recent/random sorting, favorites, preview, add destination and imported-sound editing. Unknown tags stay unknown; deterministic order and rating persistence must survive restart.
- [ ] Make import, missing-content repair and library installation obvious. Keep app installation sample-free; optional libraries are independently versioned and removable without breaking setlists silently.
- [ ] Complete MIDI learn conflicts/unlearn/reset, primary/secondary inputs, velocity scaling, monitor, tempo/metronome, transposition and audio settings with persistence and clear device status.
- [ ] Create a page-by-page behavior matrix with observed reference behavior, implemented state and live test evidence. Cover every menu, settings tab, library modal, patch/sound/effect editor and error state. No demo/Ultimate-only claim without evidence.

## P1 — UI and accessibility

- [ ] Finish wheel geometry, ridge/lighting rendering, position indication, drag sensitivity, hardware synchronization and snapshot behavior at all supported window/device sizes.
- [ ] Finish effect-panel layouts, grouped controls, labels/units, faders/knobs, numeric entry, preset menus, active/bypass state and Confirm/Discard placement. Map percentage controls to measured DSP tapers rather than relabeling Hertz values.
- [ ] Finish library modal dimensions/column behavior, scrolling, filter chips, empty/loading/error states, preview/add flow and dismissal without losing edits.
- [ ] Establish StageKeys' own release visual identity and assets while preserving the validated workflow. Audit contrast, readable minimum text size, keyboard navigation, VoiceOver labels, touch targets, focus and scaling.
- [ ] Verify Mac resizable/full-screen behavior and physical iPad landscape/portrait, split view and iPhone compact layouts. No clipped controls or hidden essential actions.

## P0/P1 — persistence, distribution and support

- [ ] Atomic saves, schema-version migrations, recovery from interrupted writes, autosave/undo and recoverable backups tested with old and deliberately damaged sessions. Never silently replace a failed load with defaults.
- [ ] Restore a portable library and setlist on a clean device; preserve identities, original sample hashes, effects, plugin references, tags and edits. Private backup is not redistribution permission.
- [ ] Complete a release content/asset/dependency provenance review and retain required notices. Ship only assets with established redistribution rights; keep user/private vendor libraries out of app binaries and public fixtures.
- [ ] Sign and notarize the Mac distribution, verify clean-machine install/update/rollback, and complete iOS signing/TestFlight/App Store preparation for intended targets. Current local ad-hoc signing is not public distribution readiness.
- [ ] Publish supported OS/hardware/storage/plugin/conversion versions and release notes. Set explicit beta limitations; no blanket 1:1, all-MainStage or crash-proof claims.
- [ ] Add repeatable CI builds, parser/processing tests, portable fixtures, package-content checks, sanitizer checks and release artifact validation. Extend to hardware/audio regression where automation alone is insufficient.
- [ ] Provide opt-in diagnostics with device/buffer/underrun information, user-controlled audio checks, actionable logs and privacy documentation. No credentials, private samples, setlists or plugin state in automatic reports.
- [ ] Write first-run onboarding, conversion troubleshooting, MIDI/audio setup, backup/recovery instructions, plugin support guidance and a support/issue process. Run a private beta on users' real rigs and close every release-blocking defect.

## Later — our own AI patch builder

- [ ] Design an independent builder that uses StageKeys' documented sound/effect schema and only the user's installed, authorized content. Do not call, scrape or depend on Sunday Keys' proprietary builder.
- [ ] Generate a previewable draft with validated bounded parameters and explicit missing content; audition, edit, undo and Confirm before replacing a patch. Never execute generated scripts or trigger unapproved downloads/purchases.
- [ ] Evaluate musical usefulness, routing safety, level/headroom, reproducibility, latency/cost and offline/manual fallback. Make remote data sharing opt-in and explain what leaves the device.
- [ ] Define whether it belongs after v1 or in a later beta. Core conversion, audio and stability gates take priority.

## Definition of public-ready

All applicable P0 gates have recorded evidence on the supported release platforms; P1 scope is explicitly completed or excluded from the advertised release. There are no known unexplained clicks, extra notes, silent supported imports, data-loss bugs or unstable supported plugins. Users can import a declared-supported MainStage patch, understand any exceptions, play a full rehearsal, save/reopen and recover their setup without developer assistance.

Platform references: Apple's [Audio Unit hosting guidance](https://developer.apple.com/documentation/audiotoolbox/incorporating-audio-effects-and-instruments) distinguishes third-party AUv3 on iOS from macOS AUv2/AUv3 hosting. Apple's [Mac notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) describes Developer ID distribution. These are platform requirements/references, not evidence that StageKeys has passed them.
