# Rename the app to Jarvis (display only)
Status: done
Type: task

PRODUCT_NAME and display name become Jarvis, installed as /Applications/Jarvis.app. build-and-install.sh paths, the Keepalive target, the Dock entry and the visible strings change. The bundle ID, the REQ/designated-requirement line, dayframe://, settings keys, the logger subsystem and the data folder stay. Verify recording continues (tccd 0 'Failed to match', screenshots advancing) before removing Dayframe.app.

## Comments
- 2026-10-14: code renamed (CHANGELOG 12:26). Install + recording check pending.
- 2026-10-14 13:50: Jarvis.app installed; recording verified (frames every 10 s until the screen locked; tccd ScreenCapture 0 mismatches).
