# Import integrity, level feedback and mixer alignment — 0.52

Native MainStage processing previews/conversion verify retained `data.plist` and selected channel-strip bytes against the source import hashes before translating settings. Changed documents or missing integrity records require reimporting the original. This protects against stale/mismatched effect and MIDI settings; it does not authenticate the source publisher or claim full conversion coverage. Original samples are unchanged.

Gain matching now displays the proposed post-trim RMS and differentiates peak-ceiling constraints from the −24…+12 dB trim range. A target can remain unreachable even when the probe is valid. Reference reuse uses the proposed achievable level. The probe is an RMS/sample-peak estimate, not LUFS/true-peak normalization; keep reviewing sustained chords and articulations.

Mixed patches previously placed MIDI/effect slots and faders lower in sounds with imported Rack FX links. All loaded modules now reserve the same link row whenever any loaded sound has a rack, keeping those controls aligned. The link still opens the imported processing view; rack DSP and saved settings do not change.

Verification: import hash corruption/missing-record regressions; actual private Steinway CST and patch conversion, sample hashes and duplicate-aware reimport; gain limits/retargeting plus an actual hosted AU; universal Mac and iOS Simulator release builds. No physical iOS qualification or new live audio calibration. Issues #5, #19 and #25 remain open for their broader release gates.
