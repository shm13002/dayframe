#!/bin/bash
# Gives Hermes Jarvis's system tools and Dayframe's timeline. Safe to re-run.
#   ./install-bridge.sh          copy + enable the bridge plugin, tool search off, dayflow MCP
#   ./install-bridge.sh --undo   take all of that back (tool search returns to its old value)
#   ./install-bridge.sh --test   run the bridge's own tests with Hermes's Python
# Mirrors Herald OS's scripts/bootstrap.sh (MIT, Luke The Dev); see bridge/JARVIS-CHANGES.md.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN="$HERE/bridge/herald-os-bridge"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
ROOT="$HERMES_HOME/hermes-agent"
HERMES="$ROOT/.hermes/bin/hermes"
[[ -x "$HERMES" ]] || HERMES="$(command -v hermes || true)"
if [[ -z "$HERMES" ]]; then
  echo "Hermes Agent isn't installed (looked in $ROOT and PATH)." >&2
  exit 1
fi
STATE="$HERMES_HOME/herald-os"
mkdir -p "$STATE"

hermes_run() { (cd "$ROOT" 2>/dev/null || true; NO_COLOR=1 "$HERMES" "$@" </dev/null); }

step() {
  local what="$1" output status=0
  shift
  echo "  hermes $*: $what"
  output="$(hermes_run "$@" 2>&1)" || status=$?
  if [[ $status -ne 0 ]] || grep -q '^[[:space:]]*✗' <<<"$output"; then
    echo "  FAILED (exit $status):" >&2
    echo "$output" | tail -15 >&2
    exit 1
  fi
}

# The bundled `dayflow` CLI of the installed app (its `mcp` subcommand is the timeline server).
dayflow_cli() {
  for app in /Applications/Jarvis.app /Applications/Dayframe.app; do
    [[ -x "$app/Contents/Helpers/dayflow" ]] && { echo "$app/Contents/Helpers/dayflow"; return; }
  done
}

case "${1:-}" in
--test)
  # The tests stub Hermes, so any Python 3.9+ with pytest runs them (Xcode's python3 has it).
  cd "$PLUGIN/tests" && exec python3 -m pytest -q -p no:cacheprovider .
  ;;
--undo)
  echo "Taking Jarvis's changes out of Hermes"
  hermes_run mcp remove dayflow >/dev/null 2>&1 && echo "  removed the dayflow MCP server"
  hermes_run tools disable herald_os >/dev/null 2>&1 && echo "  disabled the herald_os toolset"
  hermes_run plugins disable herald-os-bridge >/dev/null 2>&1 && echo "  disabled the plugin"
  if [[ -f "$STATE/tool-search-before" ]]; then
    step "puts tool search back" config set tools.tool_search.enabled "$(cat "$STATE/tool-search-before")"
    rm -f "$STATE/tool-search-before"
  fi
  link="$HERMES_HOME/plugins/herald-os-bridge"
  [[ -e "$link" ]] && rm -rf "$link" && echo "  removed $link"
  rm -f "$STATE/bridge-enabled"
  echo "Done."
  exit 0
  ;;
esac

echo "Copying the system tools into Hermes"
# A copy, not a link into this repo: the repo lives in ~/Documents, and Hermes (a child of Jarvis)
# reading it would count as Jarvis reading Documents (a TCC Files & Folders request).
mkdir -p "$HERMES_HOME/plugins"
link="$HERMES_HOME/plugins/herald-os-bridge"
[[ -L "$link" ]] && rm -f "$link"
rsync -a --delete --exclude __pycache__ --exclude tests "$PLUGIN/" "$link/"
echo "  $link (copy of $PLUGIN)"

step "adds it to plugins.enabled" plugins enable herald-os-bridge
step "adds herald_os to the saved toolsets (it only serves Jarvis's own sessions)" tools enable herald_os

# Hermes otherwise hides plugin tools behind tool search, and the agent falls back to shell
# commands. Record the old value once so --undo can put it back.
before="$(hermes_run config get tools.tool_search.enabled 2>/dev/null | tail -n 1 | tr -d '[:space:]')"
if [[ "$before" != "off" ]]; then
  [[ -f "$STATE/tool-search-before" ]] || echo "${before:-auto}" >"$STATE/tool-search-before"
  step "turns tool search off (was ${before:-unset})" config set tools.tool_search.enabled off
fi

cli="$(dayflow_cli)"
if [[ -n "$cli" ]]; then
  # Already registered for this app path? (`mcp list` shortens paths, so read the config.)
  if ! grep -q "$cli" "$HERMES_HOME/config.yaml" 2>/dev/null; then
    hermes_run mcp remove dayflow >/dev/null 2>&1 || true
    # `mcp add` asks "Enable all 8 tools? [Y/n/select]" and cancels on a closed stdin: answer yes.
    echo "  hermes mcp add dayflow: lets Jarvis read the Dayframe timeline"
    added="$(cd "$ROOT" && printf 'y\n' | NO_COLOR=1 "$HERMES" mcp add dayflow --command "$cli" --args mcp 2>&1)"
    if ! grep -q "dayflow" <<<"$(hermes_run mcp list 2>&1)" || grep -q "Cancelled" <<<"$added"; then
      echo "  FAILED to add the dayflow MCP server:" >&2
      tail -5 <<<"$added" >&2
      exit 1
    fi
  fi
else
  echo "  (no installed Jarvis/Dayframe app yet: skipped the dayflow MCP server)"
fi

touch "$STATE/bridge-enabled"
echo "Done. Jarvis's sessions now have the system tools."
