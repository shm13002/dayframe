#!/bin/bash
# Installs the fast Piper voice and keeps it running.
# Alan (en_GB-alan-medium) stands in until a trained Jarvis voice exists.
# Safe to re-run. The copy lives in ~/jarvis-piper, outside ~/Documents, so the
# LaunchAgent is not reading this project folder (a TCC Files & Folders request).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/jarvis-piper"
STOCK="$DEST/stock/en_GB-alan-medium.onnx"
VOICE_DIR="$DEST/voice"
VOICE="$VOICE_DIR/en_GB-alan-medium.onnx"
PY="$DEST/.venv/bin/python"
LABEL=local.jarvis.piper
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

[[ -f "$STOCK" && -f "$STOCK.json" ]] || {
  echo "Alan is not on disk at $STOCK" >&2
  exit 1
}
[[ -x "$PY" ]] || {
  echo "Piper's Python is not at $PY" >&2
  exit 1
}

mkdir -p "$VOICE_DIR" "$HOME/Library/LaunchAgents"
# An APFS clone shares the existing blocks, so this does not spend another 60 MB.
rm -f "$VOICE" "$VOICE.json"
cp -c "$STOCK" "$VOICE"
cp -c "$STOCK.json" "$VOICE.json"
cp "$HERE/piper_server.py" "$DEST/piper_server.py"

cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PY</string>
    <string>$DEST/piper_server.py</string>
    <string>--voice</string>
    <string>$VOICE</string>
    <string>--port</string>
    <string>5056</string>
  </array>
  <key>WorkingDirectory</key><string>$DEST</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/jarvis-piper.log</string>
  <key>StandardErrorPath</key><string>/tmp/jarvis-piper.log</string>
</dict></plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if ! launchctl bootstrap "gui/$(id -u)" "$PLIST"; then
  # bootstrap returns an I/O error when the agent is already loaded. Restart it in place.
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
fi
echo "Fast voice agent active ($LABEL, 127.0.0.1:5056, Alan)."
