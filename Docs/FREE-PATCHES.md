# Free Sunday Sounds patches and StageKeys

Inspected October 13, 2026. Source: [Sunday Sounds free patch archive](https://sundaysounds.com/pages/insiders-free-patches). The archive lists volumes 1–10, MainStage and Ableton versions, and explicitly says these patches are not compatible with the Sunday Keys App.

StageKeys uses its own C synthesizer for its three included sounds. It now also uses Apple's sampler for SF2/DLS banks, WAV/AIFF/CAF samples and compatible `.aupreset` sampler instruments. Installed AU instruments can run inside StageKeys. JSON stores StageKeys patches, channel settings, MIDI effects and plug-in state; it is not a sound waveform format.

All ten MainStage installers were downloaded and their payloads inspected without running installer scripts. They contain `.patch` bundles, binary `.cst` channel-strip settings and MainStage metadata. None of these ten payloads contains standalone WAV/AIFF/CAF/SF2/DLS audio. The channel strips rely on MainStage's instruments/effects; one inspected strip identifies Sculpture. Renaming a CST to AUPRESET or WAV cannot convert it.

| MainStage volume | Patch bundles | Channel-strip files |
|---|---:|---:|
| 1 | 231 | 286 |
| 2 | 23 | 37 |
| 3 | 13 | 13 |
| 4 | 13 | 13 |
| 5 | 13 | 13 |
| 6 | 13 | 13 |
| 7 | 13 | 13 |
| 8 | 13 | 13 |
| 9 | 13 | 13 |
| 10 | 13 | 13 |

Counts include alternative/layered patches within the packages, not unique marketed sounds. A machine-readable inventory accompanies this report.

The inspected Ableton Volume 1 download is a ZIP containing a `.alp` Live Pack (roughly 717 MB ZIP). The ALP is a gzip-wrapped Ableton archive, not a directly playable sound bank. The remaining nine Ableton archives were not downloaded. Their exact internal devices and sample contents remain unverified.

## Using these packs now

On Mac, open a channel's sound browser → **Host Patches** → **Open Host Patch…**. Choose a MainStage `.patch`, Ableton `.adg`, or `.alp`. StageKeys opens the original host and assigns the channel to its virtual MIDI source. In the host, select **StageKeys to External App** as input, select the channel's MIDI channel, and load the patch. StageKeys sends notes, note-offs, sustain, CC7 level and CC10 pan. Configure the host's audio separately. A Live Pack must first be installed/opened by Ableton and a playable rack selected there.

This MIDI route has an automated sender/receiver test. MainStage/Ableton patch playback and audio return into StageKeys are not yet end-to-end verified. MainStage is installed on this Mac; Ableton was not found. Use distinct output MIDI channels when several modules control separate host instruments.

For direct iPad/iPhone playback, use an available AUv3 instrument or import compatible sampler/sample files. MainStage's native instruments and Ableton's rack devices are not portable AUv3 plug-ins. An alternative is to render a multi-sample instrument in the original host, then import the exported audio; StageKeys currently maps single samples chromatically from middle C and does not yet have a multi-sample-zone authoring UI.

Free download does not establish permission to redistribute the packs with StageKeys. The downloaded installer includes an end-user license restricting sharing of sounds and derived patches. These downloads stay in local analysis scratch storage and are excluded from StageKeys app/source distributions. Independent StageKeys synth sounds remain the included library.
