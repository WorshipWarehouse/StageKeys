#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build=$(mktemp -d "${TMPDIR:-/tmp}/stagekeys-reverb.XXXXXX")
trap 'rm -rf "$build"' EXIT HUP INT TERM
for test in CreamCoatTests ReverbPredelayTests RoomStereoTests SilverEarlyReflectionTests ShimmerQualityTests ShimmerTailTests; do
    xcrun clang -std=c11 -O1 -g -fsanitize=address,undefined \
        "$repo/Tests/$test.c" "$repo/Sources/Synth.c" "$repo/Sources/CreamCoat.c" \
        -framework CoreMIDI -o "$build/$test"
    "$build/$test"
done
