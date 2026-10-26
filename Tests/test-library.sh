#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
build=$(mktemp -d "${TMPDIR:-/tmp}/stagekeys-library.XXXXXX")
trap 'rm -rf "$build"' EXIT HUP INT TERM
xcrun clang -std=c11 -O2 -c "$repo/Sources/Synth.c" -o "$build/Synth.o"
xcrun clang -std=c11 -O2 -c "$repo/Sources/CreamCoat.c" -o "$build/CreamCoat.o"
sources=(
    "$repo/Sources/MIDIControlTarget.swift"
    "$repo/Sources/Models.swift"
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
if (( $# )); then tests=("$@"); else tests=(PatchDraftPlanTests ManualMIDIDestinationRefreshTests PluginParameterModelTests PrimaVerbModelTests EffectPresetTests DenseHostedTests ReverbTransitionTests LibraryBrowserTests SoundRatingTests LibraryNoteRangeTests SoundLibraryTests ImportedSoundRetentionTests MainStagePatchTests StageKeysSamplerTests SamplerAttackTests AudioDiagnosticRecorderTests InstrumentGainMatchTests EXSEnvelopeTests EXSVoiceControlsTests EXSSplitRegionTests LibraryBackupTests TonicPadTests MainStageProcessingTests MainStageControllerDefaultsTests EXSReferenceIdentityTests EXSCrossfadeNeutralTests SamplerHostVelocityTests NativeSamplerGroupTests PianoFidelityTests SamplerBoundaryRegressionTests SamplerStreamingStressTests AudioUnitCatalogTests MIDISetupTests SessionRecoveryTests); fi
for test in "${tests[@]}"; do
    xcrun swiftc -DDEBUG -import-objc-header "$repo/Sources/Bridge.h" \
        -module-cache-path "$build/modules" "${sources[@]}" "$repo/Tests/$test.swift" \
        "$build/Synth.o" "$build/CreamCoat.o" -framework CoreMIDI -lz -o "$build/$test"
    if [[ "$test" == EXSImportTests && -n "${STAGEKEYS_EXS_FIXTURE:-}" && -n "${STAGEKEYS_EXS_ROOT:-}" ]]; then
        STAGEKEYS_DATA_DIR="$build/data-$test" "$build/$test" "$build/exs-scratch" "$STAGEKEYS_EXS_FIXTURE" "$STAGEKEYS_EXS_ROOT"
    else
        STAGEKEYS_DATA_DIR="$build/data-$test" "$build/$test"
    fi
done
