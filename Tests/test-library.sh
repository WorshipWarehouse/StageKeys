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
    "$repo/Sources/ExternalSound.swift"
    "$repo/Sources/EXSCaptureCompatibility.swift"
    "$repo/Sources/BuiltinEffectUnit.swift"
    "$repo/Sources/ImportedAudioGraph.swift"
    "$repo/Sources/ExternalInstruments.swift"
    "$repo/Sources/ExternalMIDIOutput.swift"
    "$repo/Sources/AudioController.swift"
    "$repo/Sources/SamplerInterchange.swift"
    "$repo/Sources/AbletonImport.swift"
    "$repo/Sources/AbletonArchive.swift"
    "$repo/Sources/SundayFactoryVoicing.swift"
    "$repo/Sources/SoundLibrary.swift"
    "$repo/Sources/LibraryBrowserModel.swift"
    "$repo/Sources/SnapshotMorph.swift"
    "$repo/Sources/Store.swift"
)
for test in LibraryBrowserTests SoundRatingTests LibraryNoteRangeTests; do
    xcrun swiftc -DDEBUG -import-objc-header "$repo/Sources/Bridge.h" \
        -module-cache-path "$build/modules" "${sources[@]}" "$repo/Tests/$test.swift" \
        "$build/Synth.o" "$build/CreamCoat.o" -framework CoreMIDI -lz -o "$build/$test"
    STAGEKEYS_DATA_DIR="$build/data" "$build/$test"
done
