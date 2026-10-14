# Jarvis tab: conversation, tools and approvals
Status: done
Type: task

SidebarIcon.jarvis first. JarvisReactView loads a single-file page bundled in the app (file:// so Hermes trusts the WebSocket origin). Web/src/jarvis: vendored upstream gateway client, chat reducer, approval cards, session list, brain pill, Dayframe palette.

## Comments
- 2026-10-14 12:26: built and unit-tested (CHANGELOG 12:26). Live end-to-end check waits on 03 (Hermes sign-in).
