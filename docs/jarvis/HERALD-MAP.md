# Herald OS → Jarvis: capability map and protocol notes

Study of **Herald OS v0.1.0-alpha.4** (released 2026-10-13, MIT, © Luke The Dev; the local copy is `~/Downloads/Herald-OS-main`), written 2026-10-14 for the Dayframe → Jarvis work. Herald OS is an independent project. It is not affiliated with Nous Research. It runs Nous Research's open-source **Hermes Agent** (MIT) and adds system abilities through a Hermes plugin.

Jarvis takes Herald's *capabilities*, not its look. Every surface uses Dayframe's palette and brand (`DayframePalette`, `Web/src/theme/palettes.ts`). Herald's UI/UX is borrowed only where it is clearly better.

## 1. How Herald is built

| Piece | What it is | Size |
|---|---|---|
| `apps/desktop/electron/` | Electron main. It starts `hermes serve`, holds the control socket, events, crash watcher and the Mac host tools | 16k LOC |
| `apps/desktop/src/` | React renderer: pages, stores, the command registry (~346 commands), voice | 140k LOC (Office 58k, Canvas 30k) |
| `packages/hermes-client/` | Re-exports upstream Hermes `apps/shared/src` (the JSON-RPC gateway client and contract) | 168 LOC |
| `plugins/herald-os-bridge/` | Hermes plugin (Python): system tools, permission tiers, audit log, UI control | 6.7k LOC + 8 skills |
| `upstream/UPSTREAM.lock` | Pins Hermes `NousResearch/hermes-agent@f97608f178d1ffeca59860195ab7da295f7c8e5f` | — |
| `linux/` | Herald OS Linux (Fedora bootc, niri session, `herald-os` CLI) | not used by Jarvis |

Herald does not fork Hermes. The Python runtime is the user's own install (`~/.hermes/hermes-agent`).

## 2. The four pillars (the user's diagram) → Jarvis

Status: **C1–C5** = the chunk that brings it in; **Have** = Dayframe already does it; **Skip** = not planned unless asked.

### Filesystem
| Capability | Herald source | Jarvis |
|---|---|---|
| Find files (Spotlight), search by name or content | bridge `system_find_files` | C1 |
| Move, copy, rename, make folders, trash, with dry run and undo journal | bridge `system_files` (mutate; trash = destructive) | C1 |
| Read PDFs and OCR, filing hints, "file my receipts" | bridge `system_documents`, skill `file-documents` | C1 |
| Files page (browser, thumbnails, viewer) | `src/features/files/` | C4 |
| Watch folders | not in Herald | C3 (an automation trigger) |

### Applications
| Capability | Herald source | Jarvis |
|---|---|---|
| Open an app, URL or file; reveal in Finder | bridge `system_open` | C1 |
| List and quit apps | bridge `system_apps` (quit = destructive) | C1 |
| Operate Jarvis's own UI ("open missions") | bridge `os_ui` + control socket + command registry | C2 |
| Slack, Notion, GitHub, Spotify … | Hermes MCP servers and messaging platforms (Connections page) | C3 |
| Install coding agents and local-model apps | `electron/catalog/` (Homebrew) | C4 |
| Studio ("build a website for …" with a live preview) | `src/features/studio/` | C5 |
| Office: Docs, Sheets, Slides | `src/features/office/` (70k LOC) | Later. Owner asked for Herald's capabilities on 2026-10-14. Do this after C5, in Dayframe's look. See `FOR-CLAUDE-CODE.md`. |
| Canvas image editor | `src/features/canvas/` (33k LOC) | Later, same as Office. |

### System
| Capability | Herald source | Jarvis |
|---|---|---|
| System info, battery, uptime | bridge `system_info` | C1 |
| Processes ("what is using memory?") | bridge `system_processes` | C1 |
| Stop a process | bridge `system_kill_process` (destructive) | C1 |
| Disk usage | bridge `system_disk_usage` | C1 |
| Network, Wi-Fi, Bluetooth status | bridge `system_network` | C1 |
| Logs and crash reports | bridge `system_logs` | C1 |
| Volume, dark mode, Settings panes, display sleep, lock | bridge `system_control` | C1 |
| Crash help (notification → "ask Jarvis") | `electron/crash/`, bridge `crash.py`, skill `diagnose-crash` | C4 |
| Screen tools: ask about a region, OCR, QR, colour picker, screenshots | `electron/ipc/capture.ts`, `platform/mac-tools.ts` | C4 |
| System monitor page | `src/features/system/` | C4 |

### Agents and automation
| Capability | Herald source | Jarvis |
|---|---|---|
| Conversation, tool rows, approval cards | `src/features/hermes/`, `lib/chat-model.ts`, `store/requests.ts` | C1 |
| Model provider and sign-in | `/api/providers/oauth/*`, `model.options`, `/api/model/set` | C1 (CLI logins), C3 (UI) |
| Memory (`~/.hermes/memories/MEMORY.md`, `USER.md`) | Hermes-native; `src/features/memory/` | C3, next to Briefing memory |
| Skills and plugins | Hermes-native | C1 (bridge skills), C3 (page) |
| MCP tools | Hermes `/api/mcp/*` | C1 (Dayframe's own `dayflow mcp`), C3 (page) |
| Scheduled tasks | Hermes cron `/api/cron/*` | C3, merged with Briefing automations |
| Event automations: login, wake, unlock, back from a break, low battery, crash | `electron/events/` | C3 |
| Missions: plan → steps → review | `src/features/missions/` (a view over sessions and `todo.updated`) | C3 |
| Bots / profiles | `profiles.list` | C3 |
| Usage meter | `usage.bars`, `/api/analytics/usage` | C3 |
| Notifications | `store/notifications.ts` | Have (notch notices); C3 for Hermes `notification.show` |
| Pick up where you left off | `features/overview/PickUp.tsx`, `lib/continuity.ts` | Have (Briefing resume); merge in C4 |
| Command bar | `shell/CommandBar.tsx` | C2 (quick panel) |

### Voice
| Capability | Herald | Jarvis |
|---|---|---|
| Push-to-talk (`Alt+Space`) | `src/lib/voice/chained-engine.ts` | C1 |
| Speech-to-text | Hermes `POST /api/audio/transcribe` (`stt.provider`) | C1 |
| Speech | Hermes TTS providers | **Replaced.** Live lines use a prepared Jarvis phrase, then Alan (Piper, `~/jarvis-piper`, 127.0.0.1:5056). The cloned voice (`~/jarvis-voice`, 5055) is for notices and for filling the phrase cache. |
| Wake word | Hermes `wake.start/feed`, openWakeWord "hey hermes" | C2, "Hey Jarvis" |
| Voice fast path, voice approvals | `lib/voice/intents.ts` | C2 |
| Dictation into any app | `store/dictation.ts` | C4 |

### Not taken
Herald's shell look (12 themes, wallpaper, dock, window manager, fullscreen takeover), the desktop pet (Jarvis's notch eyes fill that role), widgets, i18n, and everything Linux-only (session, `herald-os` CLI, `system_os`, clipboard history, reminders, web apps, games, Windows VM).

## 3. Talking to Hermes (protocol cheat-sheet)

### Starting the backend
- **Find Hermes** in this order:
  1. `$HERALD_OS_HERMES_ROOT`
  2. `$HERMES_HOME/hermes-agent` (`HERMES_HOME` defaults to `~/.hermes`). A checkout counts only if `hermes_cli/subcommands/dashboard.py` exists. Run `<root>/.hermes/bin/hermes`, or `<root>/venv/bin/python -m hermes_cli.main`.
  3. `hermes` on PATH (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`).
- **Run** `<hermes> serve --host 127.0.0.1 --port 0`, with cwd = the runtime root.
- **Environment:**
  - `HERMES_DASHBOARD_SESSION_TOKEN=<32 random bytes, base64url>`
  - `HERMES_HOME`
  - `HERMES_DESKTOP=1`
  - `HERALD_OS=1`: the bridge's scope check needs it
  - `HERMES_PARENT_PID`
  - `HERMES_DESKTOP_READY_FILE`
  - `PYTHONUNBUFFERED=1`
  - `TERMINAL_CWD=~`
  - the login-shell `PATH`
  - Remove inherited `HERMES_SESSION_*`, `HERMES_PARENT_START_MARKER/NONCE` and `HERMES_SPAWN`.
- **Ready:**
  - a stdout line `HERMES_BACKEND_READY port=N` (or `HERMES_DASHBOARD_READY`), or `{"port":N}` in the ready file. Times out after 90 s.
  - Then poll `GET /api/status` (header `X-Hermes-Session-Token`) for up to 60 s.
- **Restart** on exit after 1 / 3 / 7 / 15 s, then give up. Quit sends SIGTERM, then SIGKILL 4 s later.

### Auth and origins (from upstream `hermes_cli/web_server*.py`)
- **REST:** every `/api/*` call carries `X-Hermes-Session-Token`. CORS allows only `http(s)://localhost|127.0.0.1` origins.
- **WebSocket:** `ws://127.0.0.1:N/api/ws?token=<token>`.
  - Hermes checks the Host header.
  - An `Origin` header, when present, must be http(s) on the bound host. Non-web origins (`file://`, `null`, `app://`) are trusted, because the token is the boundary.
  - **So Jarvis's page ships as a file in the app bundle and connects directly. REST calls go through Swift.**

### JSON-RPC methods Herald uses
| Area | Methods |
|---|---|
| Sessions | `session.create {source:"herald_os", cwd, title, profile?}`, `session.resume`, `session.list`, `session.delete`, `session.interrupt` |
| Turns | `prompt.submit {session_id, text, surface}`, `slash.exec`, `commands.catalog` |
| Other | `file.attach {session_id, name, data_url}`, `llm.oneshot`, `config.get/set`, `model.options`, `profiles.list`, `usage.bars`, `billing.state`, `wake.start/feed/stop` |

Herald calls it `herald_os`, and Jarvis keeps that id so the bridge's scope check stays unmodified.

**Events** (`{type, session_id, payload}`):
- Message stream: `message.start`, `message.delta`, `reasoning.delta`, `message.interim`, `message.complete {text, status, usage}`.
- Tools: `tool.generating`, `tool.start {tool_id, name, args}`, `tool.complete {tool_id, result_text, summary, duration_s}`.
- Session and agent: `status.update`, `session.title`, `session.info`, `subagent.*`, `todo.updated`, `cron.changed`, `notification.show`, `gateway.ready`, `error`.

**Server → client requests** (answered like RPC):
- `approval` → `{choice: once|session|always|deny}`
- `clarify`, `sudo`, `secret`
- anything else → `-32601`

The gateway client is vendored unchanged from upstream `apps/shared/src` at the pinned sha (MIT, © Nous Research).

### REST endpoints worth knowing
- **Status and config:** `/api/status`, `/api/config`
- **Sessions:** `/api/sessions/{id}/messages`
- **Automations:** `/api/cron/jobs[...]`
- **Tools and MCP:** `/api/tools/toolsets[/{name}]`, `/api/mcp/servers[...]`, `/api/mcp/catalog`
- **Messaging:** `/api/messaging/platforms`
- **Providers and model:** `/api/providers/oauth[/{id}/start|poll]`, `/api/model/set`, `/api/analytics/usage`
- **Audio:**
  - `POST /api/audio/transcribe {data_url:"data:audio/wav;base64,…", mime_type}` → `{transcript}`
  - `/api/audio/speak[-stream]`

### The bridge plugin
- **Setup:**
  - Symlink it into `~/.hermes/plugins/herald-os-bridge`.
  - `hermes plugins enable herald-os-bridge`
  - `hermes tools enable herald_os`
  - Optionally `hermes config set tools.tool_search.enabled off` (save the old value first).
- **Scope:** tools are offered only when the session `source` is `herald_os` and the backend has `HERALD_OS=1`. The `hermes` CLI, Telegram and cron never get them.
- **Tiers:**
  - `read` runs.
  - `act` runs and notifies.
  - `mutate` asks; "session" and "always" stick.
  - `destructive` asks every time, and "always" can never stick.
  - Asking reuses Hermes's own `approval` request.
- **Protected paths** are refused outright: `~/.ssh`, `~/.gnupg`, `~/Library/Keychains`, `~/Library/Cookies`, Hermes `.env` and `auth.json`, and system directories.
- **Files:**
  - Policy: `~/.hermes/herald-os/permissions.yaml`
  - Audit log: `~/.hermes/herald-os/audit.jsonl` (5 MB rotation, secrets redacted)
- **Control socket** (for `os_ui`): a Unix socket at `~/.hermes/herald-os/control.sock` (0600). JSON lines `{cmd:"ui"|"ui-list"|"ui-state", command, args, token}`. Found through `HERALD_OS_CONTROL_SOCKET/TOKEN` or `control.json`.

## 4. Jarvis's choices
- **Brain:**
  - Grok through Hermes's xAI login is the default.
  - ChatGPT (Codex login) and Claude (`claude setup-token` → `CLAUDE_CODE_OAUTH_TOKEN`) can be switched in.
  - Local Qwen on Ollama is only the offline fallback. Its 4K context can't hold Hermes's prompt plus tools, so Jarvis says when it is in limited mode.
  - No API keys (ADR 0003).
- **Feel:** Grok Bot (quick). A study of its UX comes in C2.
- **Rename:** display only. The bundle ID `local.dayframe.app`, signing (ADR 0002), `dayframe://`, the data folder and the settings keys stay.
- **Voice:** Hermes's own TTS providers are not used. Two local servers sit beside the Hermes mix:
  - **Cloned Jarvis voice** (`~/jarvis-voice`, LaunchAgent `local.jarvis.tts`, `POST http://127.0.0.1:5055/tts`). About 50 s a sentence, so it is not used while someone is waiting.
    - Request: `Authorization: Bearer <~/jarvis-voice/service.token>`, no `Origin` header, body `{text ≤400 chars, voice:"jarvis", steps:32}`.
    - Responses: a WAV with `X-Jarvis-Verified: true`, 429 when busy, 422 when verification fails, 503 when generation fails.
  - **Alan, the fast filler** (`~/jarvis-piper`, LaunchAgent `local.jarvis.piper`, `POST http://127.0.0.1:5056/tts`). Stock Piper voice `en_GB-alan-medium`, standing in until a Jarvis voice is trained. Measured 2026-10-14: "On it." in 292 ms after the model was already loaded (860 ms on the cold call).
    - Request: `Authorization: Bearer <~/jarvis-piper/service.token>`, no `Origin` header, body `{"text"}` only, 3 s timeout, no retries.
    - `GET /health` reports `engine: piper`, `voice: en_GB-alan-medium`, `standIn: true`.
  - **Route:** live (⌥Space) is phrase cache, then Alan, then the Mac's British voice. Notices are phrase cache, then the cloned voice, then Alan, then the Mac voice.
  - **2026-10-14 notes:** training a Piper Jarvis voice on this Mac was deferred (the GPU probe was already too slow; the CPU probe was not run). The owner asked for Alan in the app instead. Source is `Jarvis/voice/piper_server.py`; `Jarvis/voice/install-voice.sh` copies it to `~/jarvis-piper` (outside ~/Documents, so Hermes does not trip a Documents permission). The installed app was rebuilt the same evening. Version is still 1.4. A real ⌥Space turn has not been tried.
- **Not used:** the Jarvis HQ spec, the GenUI kit and the `DayFrameJarvis` package belong to a separate project.
