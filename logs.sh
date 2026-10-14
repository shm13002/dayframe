#!/bin/bash
# Dayframe's own log lines (os.Logger, subsystem local.dayframe.app).
#   ./logs.sh                 the last hour, every area
#   ./logs.sh 3h welcome      the last 3 hours of one area
# Areas (categories): welcome, startofday, wallpaper, island, notice, briefing, recording, usage.
# List them: grep -rn "category:" App/Dayflow
# Uses /usr/bin/log on purpose: in zsh, plain `log` is a builtin that silently does nothing.
set -euo pipefail
last=${1:-1h}
predicate='subsystem == "local.dayframe.app"'
[[ -n ${2:-} ]] && predicate+=" AND category == \"$2\""
/usr/bin/log show --style compact --info --last "$last" --predicate "$predicate"
