# herald-os-bridge in Jarvis

`herald-os-bridge/` is the Hermes plugin from **Herald OS v0.1.0-alpha.4** (MIT, © 2026 Luke The
Dev; `LICENSE` kept), `plugins/herald-os-bridge` in https://github.com/iamlukethedev/Herald-OS.
Herald OS is an independent project, not affiliated with Nous Research.

Internal ids stay as Herald named them (plugin `herald-os-bridge`, toolset `herald_os`, session source
`herald_os`, data in `~/.hermes/herald-os/`), so its scope check, permission tiers, protected paths
and audit log work unmodified.

## What Jarvis changed (keep this list short and current)

| File | Change | Why |
|---|---|---|
| `__init__.py` | `SHELL_ONLY_TOOLS` (`os_ui`, `canvas`, `docs`, `sheets`, `slides`, `system_os`) are not registered | They drive Herald's own shell, office apps or Linux CLI, which Jarvis doesn't have |
| `__init__.py` | Skills are `jarvis`, `diagnose-crash`, `file-documents` | The `herald-*` skills describe Herald's shell |
| `skills/jarvis/SKILL.md` | New | Who Jarvis is, which tools to prefer, the dayflow MCP, voice and boundaries |
| `bridge/tools.py` | `system_open` description no longer mentions Herald OS windows | Jarvis opens things in macOS |
| `bridge/tools.py` | `system_info` description points to the `jarvis` skill | Plugin skills aren't in the system prompt; tool descriptions are how Hermes finds them |
| `plugin.yaml` | Description says Jarvis | — |
| `tests/test_scope.py`, `tests/test_crash.py` | Expect the trimmed tool and skill lists | — |
| `tests/test_config_migration.py` | Removed | It tests Herald's `scripts/migrate-hermes-config.py`, which isn't vendored |

Not copied: the `herald-*` skills.

## Install

`./install-bridge.sh` copies this folder into `~/.hermes/plugins/` (a copy, so Hermes never reads ~/Documents) and enables it (idempotent). Re-run it after changing the plugin.
`./install-bridge.sh --undo` reverses it. Tests: `./install-bridge.sh --test`.
