# Review before native conversion

Refs #5. Choosing a MainStage patch/CST retains the original source and displays its report without adding playable sounds. Select the sampler channels in the report, then choose **Convert Included Instruments** or **Locate Samples and Convert Selected Channels**. Empty/out-of-range selections cannot enter conversion. The explicit step keeps preflight distinct from library mutation and preserves channel order.

The converter still validates exact retained source hashes and refuses ambiguous instrument matches. It preserves original samples without rendering or opening MainStage. Processing notes identify partial translations; a referenced EXS alone does not prove complete native fidelity. Concert traversal, comprehensive missing-content repair after relocation, and a fully transactional bulk importer remain separate release work.

## Third-party Audio Units

Refs #5. A channel strip can save a third-party Audio Unit as a `PSDD` record in the CST container. The report now lists that device with its saved type/subtype and adds a blocker naming it, instead of dropping the record because its signature was not `GAME` or `MELC`.

Observed 2026-10-26 in the private local library: 186 channel strips, 818 recognised devices, and 53 strips carrying one `PSDD` record, all named `OB-Xd`, whose following bytes decode little-endian as `aumu`/`Obxd`. The installed plug-in reports `aumu Obx3 DDSP`, a different subtype, so the report names the saved identity rather than assuming the installed plug-in matches. Reading those bytes as an Audio Unit component identity is an inference from the record layout, not a documented format.

The record is not opaque. Its payload is a MainStage plug-in-state plist with `type`, `subtype`, `manufacturer`, `version`, `name`, `data`, `element-name` and `jucePluginState` keys. All 53 records share that shape: `aumu`/`Obxd`, manufacturer `DDSP`, version `0`, preset name `Accordion OB-Xa`, a 652-byte parameter cache, and a `jucePluginState` blob that begins `VC2!`, declares its own payload length, and holds OB-Xd's XML program bank — 128 `<program>` records and 10,495 `Val_*` values, 170,910–171,090 bytes per strip. The component identity inside the plist independently confirms the four-character code reading from the record header.

The report now names the saved identity, preset name, program count and state size, and leaves the state untouched inside the retained source archive. It does not apply it. Playing these pads natively would need the same Audio Unit hosted with that vendor state applied; the saved subtype is `Obxd` while the installed plug-in is `Obx3`, so version compatibility is unverified.

This is disclosure only. No plug-in is loaded, no saved plug-in state is applied, and no channel becomes playable because of it. An unrecognised signature is still skipped: arbitrary bytes often spell `UCuA` by accident, and the synthetic regression test keeps such a record out of the device list.

### Restoring the saved state

Observed 2026-10-26 against the installed OB-Xd 3.24.0 (`aumu`/`Obx3`/`DDSP`) from a strip that saved `aumu`/`Obxd`/`DDSP`. Setting the stored class info unchanged is ignored: the host applies it only when its `subtype` matches the installed component. Replacing `type`, `subtype` and `manufacturer` with the installed component's values, leaving the vendor payload untouched, does apply it. OB-Xd then reports 14 changed parameters and re-serializes the class info at 206,597 bytes instead of the saved 170,941. Distinct strips produce distinct changes — `VoiceDetune` 0.574 and `Sustain` 0.074 for one pad, `Multimode` 0.098 and `Attack` 0.160 for another — so the saved program is what is being restored, not a fixed default.

`MainStageAudioUnit.match` performs that rewrite only for a version-changed match and leaves an exact match untouched. `Tools/ApplyMainStageAUState` runs the whole path and prints the changed parameters. The class-info setter settles asynchronously: about 0.5 s passed before parameter values reflected the change, so a restore check must wait rather than read immediately.

This is not sonic parity. The saved bank stores 82 values per program while the installed plug-in exposes 97 parameters; missing values take the plug-in's defaults, and whether the first 82 indices mean the same thing in both versions is unverified. A hosted layer needs its own listening test before anything here can be described as matched sound.

### Hosting a converted channel

Refs #5, #12. Converting a channel whose only instrument is a saved Audio Unit now creates a hosted layer instead of a blocker: `MainStageAudioUnit.hostedLayer` matches the saved identity against the components installed here, keeps the vendor payload byte-for-byte, and stores the class info on the layer, which is the document the rack restores. The channel appears in the conversion report and is selected like a sampler channel.

Availability decides the outcome. A component that is not installed, is blocked after a failed load, or has no build for this processor fails the import with a message naming it; nothing is substituted. `ExternalInstrumentRack.instruments()` supplies the installed list, and the conversion accepts an injected list so this path can be verified without third-party plug-ins present.

Observed 2026-10-26 on the private local library, using the installed OB-Xd 3.24.0: 16 of 41 patch bundles contain a saved Audio Unit, and converting six of them produced 24 hosted entries — four channels each, all `aumu/Obxd/DDSP` mapped to the installed `aumu/Obx3/DDSP` with the vendor payload intact. Loading one hosted entry through the app's own rack and restoring its stored state changed 13 of 97 parameters, so the state reaches the plug-in rather than being accepted and dropped.

Limits: a layer hosts one instrument, so a channel that saved both a sampler and an Audio Unit converts the sampler only and its notes say the plug-in state stayed in the archive; a channel holding more than one saved Audio Unit is refused rather than guessed. The conversion notes warn that a version-changed match relies on the plug-in's own parameter mapping, and that values whose meaning changed between versions fall back to its defaults. Assembly still requires every convertible channel to be converted first, so a patch that also contains sampler channels needs both conversions before it can be created. Nothing here has been listening-tested.

One defect this exposed: capturing plug-in state on patch switches replaced a layer's retained state with nothing when the plug-in was not loaded, which would have erased the saved state of an Audio Unit that is installed on one Mac and not another. `capturePluginStates` now keeps the existing state in that case.
