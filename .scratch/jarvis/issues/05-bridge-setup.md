# Vendor herald-os-bridge and link it into Hermes
Status: ready-for-agent
Type: task

Copy plugins/herald-os-bridge into Jarvis/bridge (MIT notice kept), with user-facing text saying Jarvis. JarvisBridgeSetup: symlink into ~/.hermes/plugins, hermes plugins enable, hermes tools enable herald_os, register Dayframe's dayflow MCP. Idempotent; records what it changed for undo.

## Comments
