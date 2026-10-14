#!/bin/bash
# Dayframe Briefing installer (macOS). Idempotent: safe to re-run.
set -euo pipefail
[[ "$(uname)" == "Darwin" ]] || { echo "macOS only."; exit 1; }
SRC="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Briefing/app"; LA="$HOME/Library/LaunchAgents"; LABEL=com.dayflowbriefing
# launchd starts jobs with a bare PATH; give them Homebrew (Apple Silicon + Intel) and the Ollama CLI
JOB_PATH="/opt/homebrew/bin:/usr/local/bin:/Applications/Ollama.app/Contents/Resources:/usr/bin:/bin:/usr/sbin:/sbin"

# ./install.sh --check : read-only preflight, changes nothing
if [[ "${1:-}" == "--check" ]]; then
  ok() { echo "  OK    $1"; }; no() { echo "  FIX   $1"; FAIL=1; }; warn() { echo "  WARN  $1"; }; FAIL=0
  echo "Preflight (nothing is installed or changed):"
  echo "  INFO  macOS $(sw_vers -productVersion), $(uname -m)"
  PYC="$(command -v python3 || true)"
  if [[ -n "$PYC" ]] && "$PYC" -c 'import sys,sqlite3;assert sys.version_info>=(3,9);sqlite3.connect(":memory:").execute("create virtual table t using fts5(x)")' 2>/dev/null
  then ok "python3 $("$PYC" -V 2>&1 | cut -d' ' -f2) with sqlite FTS5 ($PYC)"; else no "python3 >= 3.9 missing: xcode-select --install"; fi
  xcode-select -p >/dev/null 2>&1 && ok "Xcode Command Line Tools (git, swiftc)" || no "Command Line Tools missing: xcode-select --install"
  command -v brew >/dev/null 2>&1 || [[ -x /opt/homebrew/bin/brew || -x /usr/local/bin/brew ]] && ok "Homebrew" || warn "Homebrew missing (installer will install it)"
  [[ -d /Applications/Jarvis.app ]] && ok "Jarvis.app" || warn "Jarvis.app not installed (run ../build-and-install.sh)"
  [[ ! -d /Applications/Dayflow.app ]] && ok "Upstream Dayflow.app not present" || warn "Upstream Dayflow.app is installed; quit/uninstall it so it never shares the database with Dayframe"
  DB="$HOME/Library/Application Support/Dayflow/chunks.sqlite"
  [[ -f "$DB" ]] && ok "Dayframe database found" || warn "no database yet at $DB (open Dayframe and let it record; or set dayflow_db in ~/Briefing/config.json)"
  [[ -d /Applications/Ollama.app ]] || PATH="$JOB_PATH" command -v ollama >/dev/null 2>&1 && ok "Ollama installed" || warn "Ollama not installed (installer will install it)"
  curl -fs -m 3 http://localhost:11434/api/tags >/dev/null && ok "Ollama running" || warn "Ollama not running (open -a Ollama)"
  PATH="$JOB_PATH:$PATH" command -v sleepwatcher >/dev/null 2>&1 && ok "sleepwatcher" || warn "sleepwatcher missing (installer will brew install; without it no briefing on wake, login briefing still works)"
  if lsof -nP -iTCP:8765 -sTCP:LISTEN >/dev/null 2>&1; then
    lsof -nP -iTCP:8765 -sTCP:LISTEN | grep -qi python && ok "port 8765 (Briefing dashboard already running)" || no "port 8765 in use by another app: set dashboard_port in ~/Briefing/config.json"
  else ok "port 8765 free"; fi
  FREE=$(df -g "$HOME" | awk 'NR==2{print $4}'); [[ ${FREE:-0} -ge 8 ]] && ok "disk: ${FREE} GB free" || warn "disk: ${FREE} GB free (models need ~5-10 GB)"
  echo; [[ $FAIL == 0 ]] && echo "Ready: run ./install.sh" || echo "Fix the FIX lines, then run ./install.sh"
  exit $FAIL
fi
mkdir -p "$APP" "$HOME/Briefing/log" "$LA"

# 1) Homebrew
if ! command -v brew >/dev/null 2>&1; then
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [[ -x $b ]] && eval "$($b shellenv)"; done
fi
if ! command -v brew >/dev/null 2>&1; then
  echo "Installing Homebrew (asks for your password)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [[ -x $b ]] && eval "$($b shellenv)"; done
fi

# 2) Dependencies (never install upstream Dayflow.app; Dayframe shares its data folder)
brew list --cask ollama >/dev/null 2>&1 || command -v ollama >/dev/null 2>&1 || brew install --cask ollama
brew list sleepwatcher >/dev/null 2>&1 || brew install sleepwatcher
[[ -d /Applications/Jarvis.app ]] || echo "WARN: /Applications/Jarvis.app not found; run ../build-and-install.sh from the repo root."
if [[ -d /Applications/Dayflow.app ]]; then
  echo "WARN: /Applications/Dayflow.app is installed. Never run Dayflow and Dayframe together; consider: brew uninstall --cask dayflow"
fi

# 3) Python & Briefing files
PY="$(command -v python3 || true)"
[[ -n "$PY" ]] || { echo "python3 not found. Run: xcode-select --install   then rerun."; exit 1; }
cp "$SRC/briefing.py" "$SRC/improve.py" "$SRC/dashboard.html" "$SRC/swiftbar-briefing.5m.sh" "$APP/"
chmod +x "$APP/briefing.py" "$APP/swiftbar-briefing.5m.sh"
rm -rf "$APP/tests"; cp -R "$SRC/tests" "$APP/tests"   # the self-improvement gate runs the full suite on every candidate
# The React Briefing screen (built from ../Web by `npm --prefix Web run build`), served at /app/.
rm -rf "$APP/dist"; if [[ -f "$SRC/dist/index.html" ]]; then cp -R "$SRC/dist" "$APP/dist"; else echo "WARN: Briefing/dist not built; Dayframe falls back to its native Briefing screen."; fi
for f in tunables.json prompts.json; do [[ -f "$APP/$f" ]] || cp "$SRC/$f" "$APP/$f"; done   # keep approved tuning on re-install
# The app dir is a git repo so every self-improvement is a reviewable branch, and approve/undo is merge/revert.
if command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
  printf 'BriefingCompanion\ncompanion-Info.plist\ndist/\n__pycache__/\n*.pyc\n' > "$APP/.gitignore"
  [[ -d "$APP/.git" ]] || git -C "$APP" init -q
  git -C "$APP" add -A
  git -C "$APP" -c user.name=Briefing -c user.email=briefing@localhost commit -q -m "install $(date +%F)" || true
else echo "WARN: git not found (xcode-select --install); self-improvement proposals are disabled until it is."; fi

# 4) Ollama running + model (model chosen by RAM, editable in ~/Briefing/config.json)
pgrep -xq Ollama || open -a Ollama || true
for _ in $(seq 1 30); do curl -fs http://localhost:11434/api/tags >/dev/null && break; sleep 1; done
MODEL="$("$PY" -c "import json,sys;sys.path.insert(0,'$APP');import briefing as b;print(b.load_config()['model'])")"
echo "Model: $MODEL  (change in ~/Briefing/config.json)"
export PATH="$JOB_PATH:$PATH"
if command -v ollama >/dev/null 2>&1; then
  ollama list 2>/dev/null | awk '{print $1}' | grep -qx "$MODEL" || ollama pull "$MODEL" || echo "WARN: could not pull $MODEL; run: ollama pull $MODEL"
  ollama list 2>/dev/null | awk '{print $1}' | grep -q "^nomic-embed-text" || ollama pull nomic-embed-text || echo "WARN: no embeddings model; search falls back to keywords"
else echo "WARN: ollama CLI not found; open Ollama once, then: ollama pull $MODEL && ollama pull nomic-embed-text"; fi

# 5) Wake hook via sleepwatcher (~/.wakeup), marked block so it's idempotent
WAKE="$HOME/.wakeup"; touch "$WAKE"; chmod +x "$WAKE"
grep -q '^#!/' "$WAKE" || { printf '#!/bin/bash\n' | cat - "$WAKE" > "$WAKE.tmp" && mv "$WAKE.tmp" "$WAKE"; chmod +x "$WAKE"; }
if ! grep -q "# >>> dayflow-briefing" "$WAKE"; then
  cat >> "$WAKE" <<W
# >>> dayflow-briefing
(sleep 20; "$PY" "$APP/briefing.py" wake >> "$HOME/Briefing/briefing.log" 2>&1) &
# <<< dayflow-briefing
W
fi
brew services restart sleepwatcher >/dev/null 2>&1 || brew services start sleepwatcher || echo "WARN: sleepwatcher not running; you still get a briefing at login, just not on wake"

# 6) LaunchAgents
plist() { # name, extra-xml, args
  local f="$LA/$LABEL.$1.plist"
  cat > "$f" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL.$1</string>
  <key>ProgramArguments</key><array><string>$PY</string><string>$APP/briefing.py</string><string>$3</string></array>
  $2
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$JOB_PATH</string></dict>
  <key>StandardOutPath</key><string>$HOME/Briefing/briefing.log</string>
  <key>StandardErrorPath</key><string>$HOME/Briefing/briefing.log</string>
</dict></plist>
P
  plutil -lint -s "$f" || { echo "ERROR: invalid plist $f"; return 1; }
  launchctl bootout "gui/$(id -u)/$LABEL.$1" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$f"
}
plist login   '<key>RunAtLoad</key><true/>' wake
plist checkin '<key>StartInterval</key><integer>4500</integer>' checkin
plist distill '<key>StartInterval</key><integer>1800</integer>' distill
DEB_H="$("$PY" -c "import json;print(json.load(open('$HOME/Briefing/config.json')).get('debrief_hour',18))" 2>/dev/null || echo 18)"
plist debrief "<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$DEB_H</integer><key>Minute</key><integer>0</integer></dict>" debrief
plist report  '<key>StartCalendarInterval</key><dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>18</integer><key>Minute</key><integer>30</integer></dict>' report
plist dashboard '<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>' serve
# Self-improvement check at 02:30 (skips itself on battery / low disk; only ever creates proposals for you to approve)
plist improve '<key>StartCalendarInterval</key><dict><key>Hour</key><integer>2</integer><key>Minute</key><integer>30</integer></dict><key>LowPriorityIO</key><true/><key>Nice</key><integer>10</integer>' improve

# Optional SwiftBar menu-bar icon (only if SwiftBar is installed and has a plugin folder)
SB_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
if [[ -n "$SB_DIR" && -d "$SB_DIR" ]]; then ln -sf "$APP/swiftbar-briefing.5m.sh" "$SB_DIR/swiftbar-briefing.5m.sh"; echo "SwiftBar plugin linked."; fi

mkdir -p "$HOME/Briefing/automations"
chmod -R go-rwx "$HOME/Briefing"
PORT="$("$PY" -c "import sys;sys.path.insert(0,'$APP');import briefing as b;print(b.load_config()['dashboard_port'])")"

# Optional Companion orb: only built if Companion.swift is present in the source folder (retired by owner 2026-10-13)
if [[ -f "$SRC/Companion.swift" ]] && xcrun --find swiftc >/dev/null 2>&1; then
  cp "$SRC/Companion.swift" "$APP/Companion.swift"
  cat > "$APP/companion-Info.plist" <<'IP'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.briefing.companion</string>
  <key>CFBundleName</key><string>BriefingCompanion</string>
  <key>NSMicrophoneUsageDescription</key><string>Hold the mic button to ask a question by voice. Audio stays on this Mac.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Turns your held-to-talk question into text, on-device.</string>
  <key>NSAppleEventsUsageDescription</key><string>Reads the current browser tab URL to tell what you are working on.</string>
</dict></plist>
IP
  if xcrun swiftc -O "$APP/Companion.swift" -o "$APP/BriefingCompanion" -framework Cocoa -framework Vision \
       -framework ScreenCaptureKit -framework Speech -framework AVFoundation \
       -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$APP/companion-Info.plist"; then
    f="$LA/$LABEL.companion.plist"
    cat > "$f" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL.companion</string>
  <key>ProgramArguments</key><array><string>$APP/BriefingCompanion</string></array>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>ProcessType</key><string>Interactive</string>
  <key>EnvironmentVariables</key><dict><key>BRIEFING_PORT</key><string>$PORT</string></dict>
  <key>StandardErrorPath</key><string>$HOME/Briefing/companion.log</string>
</dict></plist>
P
    plutil -lint -s "$f"
    xattr -d com.apple.quarantine "$APP/BriefingCompanion" 2>/dev/null || true
    launchctl bootout "gui/$(id -u)/$LABEL.companion" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$f"
    echo "Companion orb running."
  else echo "WARN: Companion.swift failed to compile; the rest works without it."; fi
else
  launchctl bootout "gui/$(id -u)/$LABEL.companion" 2>/dev/null || true
  rm -f "$LA/$LABEL.companion.plist" "$APP/BriefingCompanion" "$APP/Companion.swift" "$APP/companion-Info.plist" "$HOME/Briefing/companion.log"
  # Remove any stale 'companion' entry from ~/Briefing/status.json so `briefing.py doctor` does not report it LATE
  "$PY" -c "import json,pathlib;p=pathlib.Path('$HOME/Briefing/status.json');d=json.loads(p.read_text()) if p.exists() else {};d.pop('companion',None) and p.write_text(json.dumps(d,indent=1))" 2>/dev/null || true
fi
plist nightly '<key>StartCalendarInterval</key><dict><key>Hour</key><integer>23</integer><key>Minute</key><integer>0</integer></dict>' nightly

echo
"$PY" "$APP/briefing.py" status || true
cat <<M

Installed. Next:
 1. Open Dayframe, grant Screen Recording, and choose Ollama (Qwen) or your CLI plan as its AI provider.
 2. First dialog may ask to allow "osascript"/Terminal to control the computer: allow it.
 3. Test now:  $PY $APP/briefing.py brief --force
 Automations: dashboard -> Automations tab (drafts never run without your approval)
 Dashboard: http://127.0.0.1:${PORT:-8765}   (menu bar: brew install --cask swiftbar, then rerun install.sh)
 Ask your memory:  $PY $APP/briefing.py ask "what was I doing yesterday afternoon?"
 Voice: set "speak": true in ~/Briefing/config.json
 Recording cleanup is DRY-RUN: check ~/Briefing/memory/cleanup-report.md after a night,
 then set "cleanup_enabled": true in ~/Briefing/config.json
M
