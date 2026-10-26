#!/bin/bash
# Read-only verification; never signs, uploads or accepts agreements.
set -euo pipefail
app=${1:?Usage: verify-public-mac.sh /path/to/StageKeys.app}
repo=$(cd "$(dirname "$0")/.." && pwd)
python3 "$repo/Tools/check-distribution.py" --bundle "$app"
/usr/bin/codesign --verify --deep --strict "$app"
details=$(/usr/bin/codesign -d --verbose=4 "$app" 2>&1)
if ! printf '%s\n' "$details" | /usr/bin/grep -q '^Authority=Developer ID Application:'; then
  echo 'FAIL: public Mac distribution requires Developer ID Application signing; ad-hoc/local signing is insufficient.' >&2
  exit 1
fi
if ! printf '%s\n' "$details" | /usr/bin/grep -q 'flags=.*runtime'; then
  echo 'FAIL: hardened runtime is missing.' >&2
  exit 1
fi
/usr/bin/xcrun stapler validate "$app"
/usr/sbin/spctl --assess --type execute --verbose=4 "$app"
echo 'PASS: signature, hardened runtime, stapled notarization, Gatekeeper and sample-free content'
