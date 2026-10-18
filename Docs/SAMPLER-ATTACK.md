# Imported sample attacks — investigation through v0.33.1

The reported Steinway problem persists on isolated notes, mouse-played notes and with SolaVerb bypassed, and is most apparent in the upper register. These observations narrow the investigation but do not establish that the recorded sample transient is the cause. Earlier limited resident/streamed comparisons did not isolate the defect; the later multi-instrument production-path test below does reproduce a difference. Original consolidated CAF regions were inspected without modifying them; the native conversion retains their start/root/loop mappings. The source/converted amplitude attack is very fast (0/1 ms), and velocity-dependent attack translation is still incomplete.

## Playback-only adjustment

Converted Steinway instruments now use a 40 ms minimum amplitude-envelope attack during playback. This is intentional transient softening, not a claim that the original MainStage envelope curve has been reproduced. Shorter 3–12 ms changes did not meaningfully reduce the measured live upper-register transient; the selected adjustment reduces the earliest steep onset while retaining the piano body. Decay, sustain, release, key/velocity maps, sample starts/ends, loops, effects and stored fader settings are not rewritten. A longer existing attack is retained.

Sound Settings → Settings → Attack Smoothing exposes 0–100 ms per sampler-preset sound. Zero explicitly restores the instrument's original attack. Other instruments default to zero; the automatic Steinway setting identifies the native instrument's source group names, so renaming a sound does not lose the adjustment. The setting is retained with the channel/snapshots. Changing it reloads the selected sampler's playback state; re-strike notes after changing the control.

The adjustment prepares a temporary AUPRESET and modifies only amplitude envelopes connected to amplifier gain. It also prepares the original state used for native parallel sample branches. Neither the managed preset nor the retained original instrument or audio file is changed. Graph rebuilds preserve the prepared state. Apple documents the sampler's layer-level amplitude envelopes and configurable attack control in [TN2331](https://developer.apple.com/library/archive/technotes/tn2331/_index.html); exact source envelope-shape parity is not established here.

## Verification

Private Steinway fixture checks at MIDI 60, 84 and 96 compare the unmodified and adjusted production sampler/group graphs. The first 2 ms maximum sample step decreases in each case, while the sustained piano remains audible. A test also verifies unchanged preset and CAF SHA-256 hashes. Generated-state checks cover explicit bypass, longer authored attacks, non-amplitude envelopes, unchanged sample/loop boundaries, unchanged decay/sustain/release and setting persistence.

The wider audit inspects 224 installed sampler preset states and compares twelve middle/upper-register waveforms across Felt Piano, Una Corda, Glockenspiel, Touchstone, Airy EP and Sunrise Pad with direct playback of their original native presets. The host graph adds a small fractional-sample delay; the test aligns that timing separately from waveform error and checks early attack steps independently. Aligned residuals are below 0.0001; no added onset discontinuity was found in that selection. This is a representative audio audit, not a listening certification of every library sound.

The updated Mac app is open for the user's listening check. Automated onset reduction does not by itself establish that the perceived click is completely gone. Original MainStage attack curves and velocity-dependent attack still need further translation for exact fidelity.

## v0.32 listening comparison and live capture

The user reports that the matching legacy Steinway is smooth in MainStage, including with its instrument filter bypassed. The filter was restored afterward. A short MainStage diagnostic take played MIDI 60/84/96 at velocities 50/83/127. Its expected velocity layers correlate closely with the unmodified consolidated source. The loudest reference notes clipped at the user’s +6 dB channel setting; those are not a reliable reference for peak or distortion measurements. Listening clips instead used velocity 83 at matching sustained levels.

The user heard similar attacks in those MainStage and complete StageKeys offline output clips. The tested StageKeys path includes controller-gated branches, bypassed channel processing and the output limiter. Its 40 ms setting already reduces the first 10 ms relative to the reference. This does **not** verify the live application's current effects, sustained voices, pedal-selected bank or device path, and does not establish a fix. No additional attack/filter compensation was applied on this evidence.

[Audio checks](AUDIO-CHECKS.md) capture the live application output after limiting, with its actual mix and pedal behavior. Captures are local diagnostics, excluded from source control and sound packs. Original presets and samples remain unchanged.

## v0.33 real-time streaming correction

The user's live Audio Check contains sharp jumps concentrated at render-buffer boundaries, particularly on repeated upper notes. Its peak is about 0.505 full scale, and bypassing the output limiter did not change the audible click. An offline-render comparison had missed this fault.

A real-time production-path sequence now reproduces it: MIDI 84/96/100/108 at velocity 102, repeated with note releases, a second converted instrument loading mid-take, and sustain enabled for the second half. The released streaming path produces extra abrupt boundary steps (maximum about 0.100 in this take). Keeping the original samples resident removes those extra boundary impulses; the corresponding maximum is about 0.066, occurring within the normal pitched waveform. Retaining authored preset dictionaries alone did not remove the fault and was not included as a fix.

Mac converted native instruments and their nested sample branches now explicitly disable AUSampler disk streaming before loading. Offline rendering remains resident. Ordinary SF2/plain samples and external plug-ins retain their existing playback policy. iOS retains its existing system loading policy; this Mac finding does not establish an iPad defect. Resident playback increases RAM used by active converted sounds; it does not preload the entire library. Samples, region offsets, loops, envelope settings and original instrument files are unchanged. The existing 40 ms Steinway adjustment is retained to isolate this correction from a timbre change.

`RealtimePianoTests` compares repeated upper-note live output against the same instrument's offline maximum sample step, with sustain and a second instrument's graph reload. It requires `STAGEKEYS_PIANO_PRESET` and an available Core Audio output; recordings remain temporary. The general attack, native-group and piano-fidelity checks also run. Automated reproduction and removal of the extra impulses is evidence for this fix; final confirmation still requires the user's live listening check.

## v0.33.1 original attack restored

The user reports that the click is no longer apparent with resident playback, but that StageKeys responds later than MainStage. The former automatic 40 ms Steinway attack fade was still active. It is now removed: all converted instruments default to their authored attack unless the user explicitly sets Attack Smoothing. Existing explicit smoothing settings remain respected. No sample, stored preset, filter, effect or device-buffer setting is changed by this correction.

The real-time upper-register/sustain/second-instrument regression now uses the default unsmoothed attack. It passes: live maximum sample step approximately 0.07456 versus offline source reference 0.07499. This checks that removing the workaround does not reintroduce the measured streaming impulses. It is not a measurement of complete physical-key-to-speaker latency; audio-device buffers and MIDI delivery still contribute.

Tone remains a separate parity issue. The imported legacy EXS currently omits its global filter/modulation, and a full MainStage channel strip can include additional EQ, compression and sends. The user confirmed that the current “Grand Piano and Pad” channel has been changed to the matching Steinway Grand Piano 2 sampler preset. Its channel-strip name is not the instrument name; compare that instrument and the surrounding processing before applying compensation.
