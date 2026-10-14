# For Claude Code: put Herald OS's capabilities on Jarvis

Written 2026-10-14 for the owner. Read this, then `HERALD-MAP.md` in this folder, then `AGENTS.md` and the newest `CHANGELOG.md` entries. Do that before editing.

The owner wants **Herald OS's capabilities** on Jarvis. Jarvis is the Dayframe Mac app. Herald's look stays out. Dayframe's palette, icon, and brand stay.

Herald source on this Mac: `~/Downloads/Herald-OS-main` (v0.1.0-alpha.4, MIT). The capability table, with the Herald file for each row, is `HERALD-MAP.md`.

## Already in the app (chunk 1)

Do not rebuild these.

- Hermes starts with Jarvis (`HermesBackend.swift`), session source `herald_os`, `HERALD_OS=1`.
- Jarvis tab: `Web/src/jarvis`, bundled as `jarvis.html`. The Hermes client in `Web/src/jarvis/hermes/upstream/` is vendored. Do not edit it.
- System tools: `Jarvis/bridge/herald-os-bridge`, copied into `~/.hermes/plugins` by `Jarvis/install-bridge.sh`. Record every bridge change in `Jarvis/bridge/JARVIS-CHANGES.md`. Keep the ids `herald-os-bridge` and `herald_os`.
- ⌥Space, speech-to-text through Hermes, approval cards, audit log.
- Voice: live lines use the phrase cache, then Alan (Piper, `~/jarvis-piper`, port 5056), then the Mac voice. The cloned voice on port 5055 is for notices and for filling the cache. Do not restart Piper training. Do not edit `~/jarvis-voice/tts_server.py`.

## What "the whole thing" means

Bring over every capability in `HERALD-MAP.md` sections Filesystem, Applications, System, Agents and automation, and Voice.

Leave these out. They are Herald's shell, not a capability the owner asked for:

- Herald's window manager, dock, wallpaper, 12 themes, fullscreen takeover
- The desktop pet (the notch eyes already do that job)
- Widgets, i18n
- Linux-only pieces: the Fedora session, `herald-os` CLI, `system_os`, clipboard history, reminders, web apps, games, Windows VM

Office (Docs, Sheets, Slides) and the Canvas image editor were previously marked Skip. The owner has now asked for Herald's capabilities, so they are in scope. Do them last. They are about 70k and 33k lines in Herald. Restyle them to Dayframe. Do not paste Herald's theme in.

## Order

One chunk at a time. Inside a chunk, one ticket at a time, from `.scratch/jarvis/issues/`. Finish and commit a slice before starting the next.

1. **Chunk 2, presence.** A quick panel under the notch. "Hey Jarvis" (Hermes `wake.start` / `wake.feed`, phrase "hey jarvis"). The control socket and command registry, so Jarvis can operate its own UI (`os_ui`). Voice shortcuts for common intents. Ask the owner before any screen recording of Grok Bot.
2. **Chunk 3, HQ pages.** Missions. Memory, next to Briefing memory. Automations (Hermes cron, event triggers, Briefing automations). Connections (MCP and messaging). Usage. Skills. Sign-in UI for the brains. Hermes `notification.show` into the notch.
3. **Chunk 4, Mac depth.** Files page. Crash help. Screen tools (ask about a region, OCR, QR, colour, screenshot). Dictation into other apps. Installing apps. System monitor. Merge "pick up where you left off" with Briefing.
4. **Chunk 5.** Studio: build something with a live preview.
5. **Then Office and Canvas**, each as its own project, Dayframe's look, after chunks 2–5 work.

Do not tag a release or copy a version folder unless the owner asks. The running app is still version 1.4.

## How to work in this repo

Follow `AGENTS.md`.

- A ticket, then a failing test, then the code.
- `./check.sh` until it says `all clean`. `./check.sh --app` when Swift changed. Stop if `df -h ~` shows under 3 GB free, unless `DAYFRAME_LOW_DISK_OK=1` and at least 1 GB is free.
- A dated `CHANGELOG.md` entry. One commit per entry. The hook runs `./check.sh --staged`.
- Display name is Jarvis. Do not rename the bundle id `local.dayframe.app`, `dayframe://`, settings keys, the logger subsystem, or the data folder.
- Do not change how `build-and-install.sh` signs the app (ADR 0002). Screen Recording depends on it.
- Do not use the Jarvis HQ spec, the GenUI kit, or the `DayFrameJarvis` package. Those belong to a different project.
- Another app is also called Jarvis: `~/Applications/Jarvis.app`. Never `pkill -x Jarvis`. Match `^/Applications/Jarvis.app/Contents/MacOS/Jarvis`.
- Ask the owner before every download. Give the name, the source, and the size.
- Brain stays Grok by default, no API keys. Qwen is only the offline fallback.

## Done for a chunk

The capability works from the Jarvis tab or from ⌥Space, with the same approval rules Herald uses (read runs, mutate asks, destructive asks every time). `./check.sh --app` is clean. The changelog names what you actually ran, and names anything the owner still has to try on the Mac.
