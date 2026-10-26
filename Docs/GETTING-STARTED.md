# StageKeys development beta

StageKeys is a development build. Begin with the independent starter sounds and a quiet listening level. Connect a powered USB MIDI keyboard with a data cable. Settings → MIDI shows detected inputs; use Plug and Play Defaults to accept all channels/devices. The MIDI monitor confirms incoming notes. If notes arrive but audio is silent, check the selected output, master, loaded sound fader, mute, key/velocity ranges and Audio Running. Turning a keyboard on must not require relaunching.

Use **Import Sounds** for declared-supported MainStage sampler assets. Import exact original instruments/samples, review preflight and conversion notes, and use Locate for missing content. A synth engine or unrecognized processor marked unsupported is not faithfully converted. Keep the original patch and a separate backup. StageKeys does not need MainStage to play a supported native conversion. Mac Audio Units require the compatible installed plug-in and its own licensed library; proprietary containers are not native sampler imports. iOS requires an iOS AUv3 build. VST3 is not hosted directly.

Save a setlist before rehearsal. Export it and use the separate library backup workflow for the referenced samples. A setlist alone does not contain the sound library. Test restoration and missing-content repair before depending on another computer. Do not remove the only copy of an imported library. Keep the known-good app for rollback.

For a problem, copy **Settings → Audio → Copy Support Diagnostics**, review the local clipboard text, and include the trigger, expected/actual result, reproducible steps and app version in a private GitHub issue. The report excludes device names/IDs, paths, MIDI messages, audio, setlists and plug-in state. Unknown underruns are omitted rather than reported as zero; output latency is reported by Core Audio, not a physical keyboard measurement. Nothing is uploaded automatically. Never include credentials or licensed sample files in a public report.

**Record 30-Second Audio Check** is a separate opt-in recording of your actual performance to a local file. Stop it manually or let it finish. Review recordings before choosing to share them; they can contain your music. Audio checks are not automatically attached to diagnostics.

Private beta qualification must include complete rehearsal sessions, recovery after route changes, hosted-plug-in compatibility and supported physical iOS devices. Track blockers in the release issues; passing synthetic tests does not establish public readiness.
