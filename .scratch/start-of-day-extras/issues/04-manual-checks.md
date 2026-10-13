# Checks only the user can do
Status: ready-for-human
Type: task

1. Log out and back in. Expect the first-launch welcome, then Start of day. `./logs.sh 10m welcome` shows the login decision.
2. Lock the Mac for 10+ minutes, then unlock. Expect the daily wake. `./logs.sh 20m welcome` shows the unlock decision.
3. With an external display: check the cover on every screen and where the windows land.
4. Grant Accessibility (System Settings › Privacy & Security › Accessibility › Dayframe), then press Run now in Settings › Start of day.
5. In Shortcuts, make a shortcut named "Work Focus" with the Set Focus action (Work, On). Then pick it in Settings › Start of day › Focus and press Run now.
6. Sign the Grok CLI in: `~/.grok/bin/grok login`. Then Settings › Providers › Grok › Test, and Settings › MCP / CLI › Grok CLI › Connect.

## Comments

- 2026-10-13 11:42: in-app smoothness is verified by Claude through `dayframe://welcome-preview`: daily wake 59 fps, first launch 60 fps. The four checks above remain the user's.
