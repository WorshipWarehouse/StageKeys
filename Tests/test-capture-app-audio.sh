#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build=$(mktemp -d "${TMPDIR:-/tmp}/stagekeys-app-capture.XXXXXX")
trap 'rm -rf "$build"' EXIT HUP INT TERM
xcrun swiftc -parse-as-library -module-cache-path "$build/modules" \
    "$repo/Tools/CaptureAppAudio.swift" -o "$build/capture-app-audio" \
    -framework ScreenCaptureKit -framework AVFoundation -framework CoreMedia
if "$build/capture-app-audio" >/dev/null 2>&1; then
    echo "capture tool accepted missing arguments" >&2
    exit 1
fi
echo "PASS: app-specific audio capture helper compiles and rejects an invalid request"
