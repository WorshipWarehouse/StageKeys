#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
build=$(mktemp -d "${TMPDIR:-/tmp}/stagekeys-library.XXXXXX")
trap 'rm -rf "$build"' EXIT HUP INT TERM
xcrun clang -std=c11 -O2 -c "$repo/Sources/Synth.c" -o "$build/Synth.o"
xcrun clang -std=c11 -O2 -c "$repo/Sources/CreamCoat.c" -o "$build/CreamCoat.o"
sources=(
    "$repo/Tests/FixtureSupport.swift"
    "$repo/Sources/MIDIControlTarget.swift"
    "$repo/Sources/Models.swift"
    "$repo/Sources/EQBandwidth.swift"
    "$repo/Sources/ChannelSettings.swift"
    "$repo/Sources/SetlistLibrary.swift"
    "$repo/Sources/SessionSettings.swift"
    "$repo/Sources/AudioEffectParameters.swift"
    "$repo/Sources/AudioDevices.swift"
    "$repo/Sources/MIDIPrograms.swift"
    "$repo/Sources/MIDIFXProcessor.swift"
    "$repo/Sources/MIDIInput.swift"
    "$repo/Sources/EXSNative.swift"
    "$repo/Sources/ExternalSound.swift"
    "$repo/Sources/PluginParameterModel.swift"
    "$repo/Sources/EXSCaptureCompatibility.swift"
    "$repo/Sources/BuiltinEffectUnit.swift"
    "$repo/Sources/ImportedAudioGraph.swift"
    "$repo/Sources/ExternalInstruments.swift"
    "$repo/Sources/ExternalMIDIOutput.swift"
    "$repo/Sources/AudioController.swift"
    "$repo/Sources/AudioDiagnosticRecorder.swift"
    "$repo/Sources/SamplerInterchange.swift"
    "$repo/Sources/AssetDigest.swift"
    "$repo/Sources/SundayFactoryVoicing.swift"
    "$repo/Sources/StageKeysSampler.swift"
    "$repo/Sources/MainStagePatch.swift"
    "$repo/Sources/MainStageProcessing.swift"
    "$repo/Sources/SoundLibrary.swift"
    "$repo/Sources/LibraryBackup.swift"
    "$repo/Sources/LibraryBrowserModel.swift"
    "$repo/Sources/SnapshotMorph.swift"
    "$repo/Sources/Store.swift"
)
if (( $# )); then tests=("$@"); else tests=(MainStageTapeDelayTests PersonalSoundPackTests MainStageGuidedImportTests MetadataRecoveryTests CatalogRecoveryTests MainStageFaderTests NoFactorySoundsTests SamplerStartupTests SetlistPathAliasTests StoreTests SnapshotSlotTests SessionRecoveryTests SupportDiagnosticsTests TransactionalImportTests MainStagePreflightTests PluginRecoveryTests EffectStressTests OutputMeterTests MainStageLayerAssemblyTests ModulationWheelTests AllSoundSlotsTests PatchDraftPlanTests ManualMIDIDestinationRefreshTests PluginParameterModelTests PrimaVerbModelTests EffectPresetTests DenseHostedTests ReverbTransitionTests ExternalGraphTailTests LibraryBrowserTests SoundRatingTests LibraryNoteRangeTests SoundLibraryTests ImportedSampleContinuityTests ImportedSoundRetentionTests MainStagePatchTests StageKeysSamplerTests SamplerAttackTests AudioDiagnosticRecorderTests InstrumentGainMatchTests PatchGainTests EXSEnvelopeTests EXSVoiceControlsTests EXSSplitRegionTests LibraryBackupTests TonicPadTests MainStageProcessingTests MainStageControllerDefaultsTests MainStageAudioUnitImportTests EXSReferenceIdentityTests EXSCrossfadeNeutralTests SamplerHostVelocityTests NativeSamplerGroupTests PianoFidelityTests SamplerBoundaryRegressionTests SamplerStreamingStressTests AudioUnitCatalogTests MIDISetupTests BuiltinEffectUnitTests NativeCreamCoatTests ParallelAudioTests PianoHeldNoteTests ModelTests GrooveTests MIDIFXTests SnapshotMorphTests EXSAmplitudeUpgradeTests EXSResponseUpgradeTests EXSVoiceUpgradeTests EXSCaptureCompatibilityTests EXSImportTests ModernEXSImportTests ModernEXSPlaybackTests MainStageAutoConversionTests MainStagePackTests ReferencedMainStageImportTests ImportedAttackAuditTests EQBandwidthTests PlugAndPlayTests ProgramChangeOptInTests AudioStartupTests ChannelSignalOrderTests PatchTranspositionTests MainStageEffectSelectionTests MainStageEffectSelectionImportTests MetronomeSettingsTests PluginInterfaceRequestTests AudioGraphTests SetlistLibraryTests MIDIInputTests ExternalMIDITests); fi
for test in "${tests[@]}"; do
    args=()
    case "$test" in
        AudioGraphTests) mkdir -p "$build/scratch/$test"; args=("$build/scratch/$test/rendered.wav") ;;
        ExternalAudioTests|SamplerInterchangeTests|SetlistLibraryTests) mkdir -p "$build/scratch/$test"; args=("$build/scratch/$test") ;;
    esac
    xcrun swiftc -DDEBUG -import-objc-header "$repo/Sources/Bridge.h" \
        -module-cache-path "$build/modules" "${sources[@]}" "$repo/Tests/$test.swift" \
        "$build/Synth.o" "$build/CreamCoat.o" -framework CoreMIDI -lz -o "$build/$test"
    if [[ "$test" == EXSImportTests && -n "${STAGEKEYS_EXS_FIXTURE:-}" && -n "${STAGEKEYS_EXS_ROOT:-}" ]]; then
        STAGEKEYS_DATA_DIR="$build/data-$test" "$build/$test" "$build/exs-scratch" "$STAGEKEYS_EXS_FIXTURE" "$STAGEKEYS_EXS_ROOT"
    else
        STAGEKEYS_DATA_DIR="$build/data-$test" "$build/$test" ${args[@]+"${args[@]}"}
    fi
done
# Native C regressions. They include ../Sources/Synth.h and link the objects built
# above, so they need no Swift sources, fixtures or audio hardware.
for test in DelayIndependentLevelsTests AudioEffectsTests ChannelDSPTests ChannelPanicTests RackTests SynthTests MetronomeTests; do
    xcrun clang -I "$repo/Sources" -std=c11 -O1 -g \
        "$repo/Tests/$test.c" "$build/Synth.o" "$build/CreamCoat.o" \
        -framework CoreMIDI -o "$build/$test"
    STAGEKEYS_DATA_DIR="$build/data-$test" "$build/$test"
done
# Tests that need hardware, private content or a specific installed third-party
# Audio Unit stay on demand; Docs/LOCAL-VERIFICATION.md classifies each one and
# Tests/test-library-gate.py fails when a test program is neither gated nor listed.
