#!/bin/bash
# Unsigned build gate; signing and physical-device qualification are separate.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
platform=${1:?Usage: verify-release.sh mac\|simulator build-directory}
build=${2:?Provide a build directory outside the source checkout}
mkdir -p "$build"
build=$(cd "$build" && pwd)
python3 "$repo/Tools/check-distribution.py" --repo "$repo"
case "$platform" in
  mac)
    scheme=StageKeysMac
    args=(-destination 'generic/platform=macOS' 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO)
    bundle="$build/Build/Products/Release/StageKeysMac.app"
    executable=StageKeysMac
    ;;
  simulator)
    scheme=StageKeysMobile
    args=(-destination 'generic/platform=iOS Simulator' -sdk iphonesimulator)
    bundle="$build/Build/Products/Release-iphonesimulator/StageKeysMobile.app"
    executable=StageKeysMobile
    ;;
  *) echo "Unknown platform: $platform" >&2; exit 2 ;;
esac
xcodebuild -project "$repo/StageKeys.xcodeproj" -scheme "$scheme" -configuration Release \
  -derivedDataPath "$build" "${args[@]}" CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$build/build.log"
python3 "$repo/Tools/check-distribution.py" --bundle "$bundle"
python3 "$repo/Tools/check-pack-document-type.py" --bundle "$bundle"
icon=
if [[ "$platform" == mac ]]; then
  /usr/bin/lipo "$bundle/Contents/MacOS/$executable" -verify_arch arm64
  /usr/bin/lipo "$bundle/Contents/MacOS/$executable" -verify_arch x86_64
  test -f "$bundle/Contents/Info.plist"
else
  test -x "$bundle/$executable"
  test -f "$bundle/Info.plist"
  # The iOS target ships Resources/Assets.xcassets; a build that loses it still
  # launches, so the artifact itself has to be checked for a real compiled icon.
  python3 "$repo/Tools/check-app-icon.py" --bundle "$bundle"
  icon=', and a declared, compiled app icon'
fi
echo "PASS: $platform Release artifact, executable, platform metadata and library-free contents$icon"
