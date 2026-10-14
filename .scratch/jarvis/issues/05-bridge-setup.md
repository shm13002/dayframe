# Vendor herald-os-bridge and link it into Hermes
Status: done
Type: task

Copy plugins/herald-os-bridge into Jarvis/bridge (MIT notice kept), with user-facing text saying Jarvis. JarvisBridgeSetup: symlink into ~/.hermes/plugins, hermes plugins enable, hermes tools enable herald_os, register Dayframe's dayflow MCP. Idempotent; records what it changed for undo.

## Comments
- 2026-10-14 12:26: built and unit-tested (CHANGELOG 12:26). Live end-to-end check waits on 03 (Hermes sign-in).
