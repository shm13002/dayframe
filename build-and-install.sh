#!/bin/bash
# Build Jarvis (formerly Dayframe) and install it to /Applications.
#   ./build-and-install.sh            build + install + relaunch
#   ./build-and-install.sh --build    build only (check that it compiles)
# Needs ~3 GB free disk while building (or DAYFRAME_LOW_DISK_OK=1 with 1 GB+ for incremental builds).
# Signing is local and stable, so the Screen Recording permission you grant once keeps working after rebuilds.
set -euo pipefail
cd "$(dirname "$0")"

FREE_MB=$(df -m "$HOME" | awk 'NR==2{print $4}')
if (( ${FREE_MB:-0} < 3000 )) && ! { [[ ${DAYFRAME_LOW_DISK_OK:-} == 1 ]] && (( ${FREE_MB:-0} >= 1000 )); }; then
  echo "Only ${FREE_MB} MB free; the build needs about 3000 MB (or set DAYFRAME_LOW_DISK_OK=1 with 1000+ MB free)."; exit 1
fi

mkdir -p build

# Web surfaces:
# - React Briefing screen (-> Briefing/dist, synced to ~/Briefing/app/dist when installed)
# - Notch-island show (-> App/Dayflow/Island/Resources/island.html, bundled in the app)
# - Start-of-day welcome show (-> App/Dayflow/Welcome/Resources/welcome.html, bundled in the app)
if command -v npm >/dev/null 2>&1; then
  echo "Building web surfaces..."
  [[ -d Web/node_modules ]] || npm --prefix Web ci --no-audit --no-fund > build/web-install.log 2>&1
  if ! npm --prefix Web run build > build/web-build.log 2>&1; then
    tail -20 build/web-build.log; echo "Web build FAILED (full log: build/web-build.log)"; exit 1
  fi
  if [[ -d "$HOME/Briefing/app" && -f Briefing/dist/index.html ]]; then
    rm -rf "$HOME/Briefing/app/dist"
    cp -R Briefing/dist "$HOME/Briefing/app/dist"
  fi
else
  echo "npm not found: skipping the web build (the app uses the last committed island.html and welcome.html)."
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
APP_BUILT=build/Build/Products/Debug/Jarvis.app
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

# Polite quit first: the app catches SIGTERM, closes the open recording segment and exits.
# Matched by full path, never by name: another app called "Jarvis" (Codex's Electron Jarvis HQ,
# ~/Applications/Jarvis.app, bundle local.jarvis.desktop) may be running and must be left alone.
# Before the rename (2026-10-14) this app was /Applications/Dayframe.app.
for exe in /Applications/Jarvis.app/Contents/MacOS/Jarvis /Applications/Dayframe.app/Contents/MacOS/Dayframe; do
  if pkill -TERM -f "^$exe" 2>/dev/null; then
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "^$exe" >/dev/null || break; sleep 0.5; done
    pkill -KILL -f "^$exe" 2>/dev/null || true
  fi
done
rm -rf /Applications/Jarvis.app
cp -R build/Build/Products/Debug/Jarvis.app /Applications/
# The pre-rename copy shares the same bundle id and data folder: two copies must never run, and
# dayframe:// links must reach Jarvis. It goes to the Trash (recoverable), not deleted.
if [[ -d /Applications/Dayframe.app ]]; then
  mv /Applications/Dayframe.app "$HOME/.Trash/Dayframe (before Jarvis) $(date +%Y%m%d-%H%M%S).app"
  echo "Moved the old /Applications/Dayframe.app to the Trash."
fi
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -f /Applications/Jarvis.app >/dev/null 2>&1 || true
# The Dock pin is path-based: point the Dayframe pin at Jarvis (only if it is there).
if python3 tools/dock-repoint.py /Applications/Dayframe.app /Applications/Jarvis.app; then
  killall Dock 2>/dev/null || true
fi
open /Applications/Jarvis.app
echo "Installed and launched /Applications/Jarvis.app"

# Jarvis: give Hermes the system tools and the timeline (skipped quietly until Hermes is installed).
if [[ -x "$HOME/.hermes/hermes-agent/.hermes/bin/hermes" ]] || command -v hermes >/dev/null; then
  Jarvis/install-bridge.sh || echo "Jarvis bridge setup failed (see above); the app still works."
fi

# Fast voice: Alan is already on disk, so the stand-in server is installed with the app.
# A trained en_GB-jarvis-medium file, once it exists, is what the server should load later.
if [[ -f "$HOME/jarvis-piper/stock/en_GB-alan-medium.onnx" || -f "$HOME/jarvis-piper/voice/en_GB-jarvis-medium.onnx" ]]; then
  Jarvis/voice/install-voice.sh || echo "Jarvis voice setup failed (see above); the app still works."
fi

# Keep-alive agent: reopens Jarvis (and Ollama) within 2 minutes if either isn't running.
AGENT=local.dayframe.keepalive
mkdir -p "$HOME/Library/LaunchAgents"
AGENT_DST="$HOME/Library/LaunchAgents/$AGENT.plist"
if ! cmp -s "Keepalive/$AGENT.plist" "$AGENT_DST"; then
  cp "Keepalive/$AGENT.plist" "$AGENT_DST"
  launchctl bootout "gui/$(id -u)/$AGENT" 2>/dev/null || true
fi
launchctl print "gui/$(id -u)/$AGENT" >/dev/null 2>&1 \
  || launchctl bootstrap "gui/$(id -u)" "$AGENT_DST"
echo "Keep-alive agent active ($AGENT)."
