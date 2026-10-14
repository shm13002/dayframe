#!/bin/bash
# <xbar.title>Dayframe Briefing</xbar.title>
# <xbar.desc>Menu-bar access to your local briefing dashboard</xbar.desc>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
PY=$(command -v python3); APP="$HOME/Briefing/app/briefing.py"
PORT=$("$PY" -c 'import json,os;print(json.load(open(os.path.expanduser("~/Briefing/config.json"))).get("dashboard_port",8765))' 2>/dev/null || echo 8765)
CTX=$(curl -fs -m 2 http://127.0.0.1:$PORT/api/context | "$PY" -c 'import json,sys;d=json.load(sys.stdin);print(len(d["open_loops"]),"|",(d["session_goal"] or "no goal")[:40])' 2>/dev/null)
N=${CTX%% |*}; echo "☀︎${N:+ $N}"
echo "---"
[[ -n "$CTX" ]] && echo "Goal: ${CTX#*| }" || echo "Dashboard offline | color=red"
echo "Open dashboard | href=http://127.0.0.1:$PORT"
echo "Briefing now | bash=$PY param1=$APP param2=brief param3=--force terminal=false"
echo "Resume last project | bash=$PY param1=$APP param2=resume terminal=false"
echo "Check-in | bash=$PY param1=$APP param2=checkin terminal=false"
echo "Debrief | bash=$PY param1=$APP param2=debrief terminal=false"
echo "Distill now | bash=$PY param1=$APP param2=distill terminal=false refresh=true"
