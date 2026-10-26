# Release regression gates

Refs #22. Pull requests and pushes run universal macOS and iOS Simulator unsigned Release builds, artifact/content validation, the portable parser corpus, the complete default library/conversion/persistence/routing suite, and reverb AddressSanitizer/UndefinedBehaviorSanitizer tests. Jobs have bounded timeouts and obsolete runs cancel. Build logs are retained for 14 days; private samples, user data and instrument recordings are not uploaded.

Run `Tools/verify-release.sh mac /private/tmp/stagekeys-release-mac` or replace `mac` with `simulator` for the same artifact gate locally. The committed Xcode project is authoritative; no project regeneration or private sound-library checkout is needed. Tests generate original fixtures at runtime. Private MainStage/Steinway comparison fixtures are deliberately absent from CI.

Unsigned CI artifacts are not public releases. Branch protection must require successful jobs before release. Hardware route/latency tests, physical iPad AUv3 qualification, reference listening, long performance soak, Developer ID signing/notarization and clean-device install remain separate recorded gates. A green workflow cannot establish those properties.
