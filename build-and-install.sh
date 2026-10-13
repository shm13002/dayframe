#!/bin/bash
# Build Dayframe and install it to /Applications.
#   ./build-and-install.sh            build + install + relaunch
#   ./build-and-install.sh --build    build only (check that it compiles)
# Needs ~3 GB free disk while building. Signing is local and stable, so the
# Screen Recording permission you grant once keeps working after rebuilds.
set -euo pipefail
cd "$(dirname "$0")"

FREE_GB=$(df -g "$HOME" | awk 'NR==2{print $4}')
if [[ ${FREE_GB:-0} -lt 3 ]]; then
  echo "Only ${FREE_GB} GB free; the build needs about 3 GB. Free some space first."; exit 1
fi

mkdir -p build

# Web surfaces: the React Briefing screen (-> Briefing/dist, deployed by Briefing/install.sh)
# and the notch-island show (-> App/Dayflow/Island/Resources/island.html, bundled in the app).
if command -v npm >/dev/null 2>&1; then
  echo "Building web surfaces..."
  [[ -d Web/node_modules ]] || npm --prefix Web ci --no-audit --no-fund > build/web-install.log 2>&1
  if ! npm --prefix Web run build > build/web-build.log 2>&1; then
    tail -20 build/web-build.log; echo "Web build FAILED (full log: build/web-build.log)"; exit 1
  fi
else
  echo "npm not found: skipping the web build (the app uses the last committed island.html)."
fi

echo "Building Dayframe..."
if ! xcodebuild -project App/Dayflow.xcodeproj -scheme Dayflow -configuration Debug \
  -derivedDataPath build -destination 'platform=macOS' \
  -skipPackagePluginValidation -skipMacroValidation build > build/last-build.log 2>&1; then
  grep -E ": error: " build/last-build.log | sed 's#.*/App/##' | sort -u | head -20
  echo "Build FAILED (full log: build/last-build.log)"; exit 1
fi
echo "Build succeeded."

# DO NOT CHANGE HOW THE APP IS SIGNED. On 2026-10-12 three different signing methods in one
# day made macOS reject the saved Screen Recording permission and recording stopped silently.
# The check below fails the build if the designated requirement ever changes.
# Stable signature without a certificate or keychain (so no password prompt):
# ad-hoc sign with a fixed designated requirement. macOS stores this requirement when
# you allow Screen Recording, and every build carries the same one, so the permission
# survives rebuilds. (Trade-off: any app calling itself local.dayframe.app would match.)
APP_BUILT=build/Build/Products/Debug/Dayframe.app
REQ='designated => identifier "local.dayframe.app"'
if [[ -d "$APP_BUILT/Contents/Helpers" ]]; then
  for helper in "$APP_BUILT"/Contents/Helpers/*; do
    codesign --force --sign - --timestamp=none "$helper" >/dev/null 2>&1 || true
  done
fi
codesign --force --sign - --timestamp=none --entitlements App/Dayflow/Dayflow.entitlements \
  -r="$REQ" "$APP_BUILT" >/dev/null 2>&1
if codesign -dr - "$APP_BUILT" 2>&1 | grep -q 'identifier "local.dayframe.app"$'; then
  echo "Signed (stable identity: local.dayframe.app); Screen Recording permission will stick."
else
  echo "Signing check FAILED:"; codesign -dr - "$APP_BUILT" 2>&1 | tail -2; exit 1
fi
[[ "${1:-}" == "--build" ]] && exit 0

# Keep the keep-alive agent from reopening the old copy while we swap it.
touch /tmp/dayframe-installing
trap 'rm -f /tmp/dayframe-installing' EXIT

# Polite quit first: Dayframe catches SIGTERM, closes the open recording segment and exits.
if pkill -TERM -x Dayframe 2>/dev/null; then
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Dayframe >/dev/null || break; sleep 0.5; done
  pkill -KILL -x Dayframe 2>/dev/null || true
fi
rm -rf /Applications/Dayframe.app
cp -R build/Build/Products/Debug/Dayframe.app /Applications/
open /Applications/Dayframe.app
echo "Installed and launched /Applications/Dayframe.app"

# Keep-alive agent: reopens Dayframe (and Ollama) within 2 minutes if either isn't running.
AGENT=local.dayframe.keepalive
AGENT_DST="$HOME/Library/LaunchAgents/$AGENT.plist"
if ! cmp -s "Keepalive/$AGENT.plist" "$AGENT_DST"; then
  cp "Keepalive/$AGENT.plist" "$AGENT_DST"
  launchctl bootout "gui/$(id -u)/$AGENT" 2>/dev/null || true
fi
launchctl print "gui/$(id -u)/$AGENT" >/dev/null 2>&1 \
  || launchctl bootstrap "gui/$(id -u)" "$AGENT_DST"
echo "Keep-alive agent active ($AGENT)."
