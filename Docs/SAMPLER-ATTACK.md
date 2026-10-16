# Imported sample attacks — v0.31

The reported Steinway problem persists on isolated notes, mouse-played notes and with SolaVerb bypassed, and is most apparent in the upper register. This identifies the sampled instrument onset rather than reverb, MIDI hardware or output clipping as the area to adjust. Live resident and streamed tests produced the same Steinway waveform. Original consolidated CAF regions were inspected without modifying them; the native conversion retains their start/root/loop mappings. The source/converted amplitude attack is very fast (0/1 ms), and velocity-dependent attack translation is still incomplete.

## Playback-only adjustment

Converted Steinway instruments now use a 40 ms minimum amplitude-envelope attack during playback. This is intentional transient softening, not a claim that the original MainStage envelope curve has been reproduced. Shorter 3–12 ms changes did not meaningfully reduce the measured live upper-register transient; the selected adjustment reduces the earliest steep onset while retaining the piano body. Decay, sustain, release, key/velocity maps, sample starts/ends, loops, effects and stored fader settings are not rewritten. A longer existing attack is retained.

Sound Settings → Settings → Attack Smoothing exposes 0–100 ms per sampler-preset sound. Zero explicitly restores the instrument's original attack. Other instruments default to zero; the automatic Steinway setting identifies the native instrument's source group names, so renaming a sound does not lose the adjustment. The setting is retained with the channel/snapshots. Changing it reloads the selected sampler's playback state; re-strike notes after changing the control.

The adjustment prepares a temporary AUPRESET and modifies only amplitude envelopes connected to amplifier gain. It also prepares the original state used for native parallel sample branches. Neither the managed preset nor the retained original instrument or audio file is changed. Graph rebuilds preserve the prepared state. Apple documents the sampler's layer-level amplitude envelopes and configurable attack control in [TN2331](https://developer.apple.com/library/archive/technotes/tn2331/_index.html); exact source envelope-shape parity is not established here.

## Verification

Private Steinway fixture checks at MIDI 60, 84 and 96 compare the unmodified and adjusted production sampler/group graphs. The first 2 ms maximum sample step decreases in each case, while the sustained piano remains audible. A test also verifies unchanged preset and CAF SHA-256 hashes. Generated-state checks cover explicit bypass, longer authored attacks, non-amplitude envelopes, unchanged sample/loop boundaries, unchanged decay/sustain/release and setting persistence.

The wider audit inspects 224 installed sampler preset states and compares twelve middle/upper-register waveforms across Felt Piano, Una Corda, Glockenspiel, Touchstone, Airy EP and Sunrise Pad with direct playback of their original native presets. The host graph adds a small fractional-sample delay; the test aligns that timing separately from waveform error and checks early attack steps independently. Aligned residuals are below 0.0001; no added onset discontinuity was found in that selection. This is a representative audio audit, not a listening certification of every library sound.

The updated Mac app is open for the user's listening check. Automated onset reduction does not by itself establish that the perceived click is completely gone. Original MainStage attack curves and velocity-dependent attack still need further translation for exact fidelity.
