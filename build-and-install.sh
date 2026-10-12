#!/bin/bash
# Build Dayframe and install it to /Applications.
#   ./build-and-install.sh            build + install + relaunch
#   ./build-and-install.sh --build    build only (check that it compiles)
# Needs ~3 GB free disk while building. After installing a new build, macOS may
# ask you to re-allow Screen Recording (the app is signed locally, not by Apple).
set -euo pipefail
cd "$(dirname "$0")"

FREE_GB=$(df -g "$HOME" | awk 'NR==2{print $4}')
if [[ ${FREE_GB:-0} -lt 3 ]]; then
  echo "Only ${FREE_GB} GB free; the build needs about 3 GB. Free some space first."; exit 1
fi

echo "Building Dayframe..."
if ! xcodebuild -project App/Dayflow.xcodeproj -scheme Dayflow -configuration Debug \
  -derivedDataPath build -destination 'platform=macOS' \
  -skipPackagePluginValidation -skipMacroValidation build > build/last-build.log 2>&1; then
  grep -E ": error: " build/last-build.log | sed 's#.*/App/##' | sort -u | head -20
  echo "Build FAILED (full log: build/last-build.log)"; exit 1
fi
echo "Build succeeded."

# Stable signature = macOS keeps the Screen Recording permission across rebuilds.
# Uses a "Dayframe Local" self-signed certificate or an "Apple Development" one if
# either is in your keychain; otherwise the app stays ad-hoc signed and macOS asks again.
APP_BUILT=build/Build/Products/Debug/Dayframe.app
# Sign by the certificate's SHA-1 so names with spaces or trust notes can't break it.
SIGN_LINE=$(security find-identity -p codesigning 2>/dev/null \
  | grep -E '"(Dayframe Local|Apple Development)' | head -1 || true)
SIGN_ID=$(echo "$SIGN_LINE" | awk '{print $2}')
SIGN_NAME=$(echo "$SIGN_LINE" | sed -E 's/^[^"]*"([^"]*)".*/\1/')
if [[ -n "$SIGN_ID" ]]; then
  codesign --force --deep --timestamp=none --sign "$SIGN_ID" \
    --entitlements App/Dayflow/Dayflow.entitlements "$APP_BUILT" >/dev/null 2>&1 \
    && echo "Signed with: $SIGN_NAME (Screen Recording permission will stick)" \
    || echo "WARN: signing with '$SIGN_NAME' failed; app stays ad-hoc signed"
else
  echo "Note: no signing certificate found, so macOS may ask for Screen Recording again (see START-HERE.md)."
fi
[[ "${1:-}" == "--build" ]] && exit 0

pkill -x Dayframe 2>/dev/null && sleep 2 || true
rm -rf /Applications/Dayframe.app
cp -R build/Build/Products/Debug/Dayframe.app /Applications/
open /Applications/Dayframe.app
echo "Installed and launched /Applications/Dayframe.app"
