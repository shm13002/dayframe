# Checks only the user can do
Status: ready-for-human
Type: task

1. Log out and back in. Expect the first-launch welcome, then Start of day. `./logs.sh 10m welcome` shows the login decision.
2. Lock the Mac for 10+ minutes, then unlock. Expect the daily wake. `./logs.sh 20m welcome` shows the unlock decision.
3. With an external display: check the cover on every screen and where the windows land.
4. Grant Accessibility (System Settings › Privacy & Security › Accessibility › Dayframe), then press Run now in Settings › Start of day.
