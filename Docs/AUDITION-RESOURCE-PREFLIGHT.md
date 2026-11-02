# Audition resource preflight

Implementation follow-up, 2 November 2026. Library audition previously began an audition session, cancelled the previous editor, panicked notes and isolated other channels before checking the selected instrument's resources. An editor preview also published its proposed draft before the loader's resource rejection. Source inspection identified this ordering; generated missing-file tests exercise the corrected paths.

Library audition now validates the layer and preflights known resources before beginning a session or changing performance ownership. Editor preview preflights before publishing its draft, changing MIDI routing or panicking notes. Known unavailable resources return the existing actionable diagnostic. A rejected library request returns no token and preserves the existing editor session; a valid subsequent preview can still use that session's original token.

`ResourceAvailabilityTests` checks missing-file rejection from both entry points, retained held notes/sustain, unchanged unit and graph generation, audible resident playback, unchanged saved bytes, and continued use of the original editor token. Its earlier resident-sample rollback tests retain their original setup; audition checks run in a separate final section.

This is resource preflight, not proof of successful decoding or AU installation. Later asynchronous AU, decoder, graph and audition teardown failures remain distinct paths requiring further work. No new reference-app parity, hardware or physical-device qualification is claimed. No GitHub issue closure, commit, signing, installation or distribution was performed.

Verification commands, outcomes and hashes are recorded in [the evidence record](Completion/audition-preflight-verification.json).

Final verification: all three focused programs passed (`ResourceAvailabilityTests`, `StoreTests`, `MissingAudioUnitTests`), and the unsigned universal Mac Release artifact/content gate passed. Full-suite and Simulator results in the preceding record belong to that earlier input set.
