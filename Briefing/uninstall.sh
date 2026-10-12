#!/bin/bash
# Removes the Dayflow Briefing add-on. Keeps ~/Briefing data unless --purge. Leaves Ollama/Dayflow/sleepwatcher installed.
set -uo pipefail
LABEL=com.dayflowbriefing; LA="$HOME/Library/LaunchAgents"
for n in login checkin distill nightly debrief report dashboard companion improve; do
  launchctl bootout "gui/$(id -u)/$LABEL.$n" 2>/dev/null; rm -f "$LA/$LABEL.$n.plist"
done
if [[ -f "$HOME/.wakeup" ]]; then
  sed -i '' '/# >>> dayflow-briefing/,/# <<< dayflow-briefing/d' "$HOME/.wakeup"
fi
SB_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"; [[ -n "$SB_DIR" ]] && rm -f "$SB_DIR/swiftbar-briefing.5m.sh"
rm -rf "$HOME/Briefing/app"
[[ "${1:-}" == "--purge" ]] && rm -rf "$HOME/Briefing" && echo "Deleted ~/Briefing (memory + logs)."
echo "Uninstalled. (To also remove deps: brew uninstall sleepwatcher; brew uninstall --cask ollama dayflow)"
