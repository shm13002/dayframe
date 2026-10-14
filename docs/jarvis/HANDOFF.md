# Jarvis handoff (2026-10-14 15:00, Claude → next AI)

Read this first, then `AGENTS.md` (how to work here), the top of `CHANGELOG.md`, and `HERALD-MAP.md` (this folder).

## What Jarvis is

Dayframe (the owner's Mac app: screen timeline + Briefing + notch island) was renamed **Jarvis**. The rename is display only: the bundle ID `local.dayframe.app`, `dayframe://`, settings keys and the data folder are unchanged. Jarvis became the owner's chief-of-staff agent by integrating **Herald OS v0.1.0-alpha.4**'s capabilities on top of **Hermes Agent** (Nous Research).

- **Installed:** `/Applications/Jarvis.app` v1.4 (tag `v1.4`, commit `efcb870`).
- **Backup:** `~/Documents/Projects/Dayframe Versions/v1.4 (2026-10-14)/`.
- **Plan:** `~/.claude/plans/okay-now-that-we-swift-lovelace.md`. Chunk 1 is done; chunks 2–5 are the roadmap.
- **Tickets:** `.scratch/jarvis/issues/`.

## How it fits together

| Piece | Where |
|---|---|
| Starts and watches `hermes serve` (random port + token, `HERALD_OS=1`) | `App/Dayflow/Core/Jarvis/HermesBackend.swift` |
| Long-lived Jarvis page, voice, notch eyes, ⌥Space | `Core/Jarvis/JarvisCoordinator.swift`, `JarvisVoice.swift`, `JarvisListener.swift`, `JarvisHotKey.swift` |
| Jarvis tab (first in the sidebar; the HQ) | `Views/UI/Jarvis/JarvisView.swift` hosts `Web/src/jarvis` (React), built into `App/Dayflow/Jarvis/Resources/jarvis.html` and loaded from file:// (Hermes trusts non-web WebSocket origins) |
| Hermes gateway client | `Web/src/jarvis/hermes/upstream/` (vendored unchanged; don't edit) |
| System tools (files, apps, processes, disk, network, logs, settings) with approval tiers and an audit log | `Jarvis/bridge/herald-os-bridge` (from Herald, MIT); changes listed in `Jarvis/bridge/JARVIS-CHANGES.md`; installed by `Jarvis/install-bridge.sh` (it **copies** the plugin to `~/.hermes/plugins`) |
| Settings › Jarvis | `Views/UI/Settings/JarvisSettingsView.swift` |
| Hermes install, config, sign-ins | `~/.hermes` (model `xai-oauth` / `grok-4.6`; the old config is in `config.yaml.before-jarvis`) |
| Jarvis's audit log and permission policy | `~/.hermes/herald-os/` |

## Verified working (2026-10-14)

- System tools, approval cards (a denial is respected and audited), and the timeline through the dayflow MCP. All three were tested end to end over Hermes's WebSocket.
- Recording keeps running after the rename.
- Tests: `./check.sh --app` → 284 app, 33 web, 104 Briefing and 359 bridge tests, all passing.

## Not yet verified (needs the owner at the Mac)

- A real ⌥Space voice turn. The ChatGPT app may own ⌥Space; Settings › Jarvis shows whether it registered.
- The Jarvis tab UI in person.

## Owner's decisions (don't re-ask)

- **Brain:** Grok is the fast default; ChatGPT and Claude can be switched in; Qwen is the offline fallback only. No API keys.
- **Look and feel:** Grok Bot's quick feel. Dayframe palette and brand, and keep the Dayframe icon. Borrow Herald UI/UX only where it is better.
- **Speed:** never slower than Herald. Herald's voice starts speaking about 1 s after the reply begins.
- **Voice:**
  - Speak a one-sentence summary, not whole answers.
  - The owner chose to **train a fast Piper Jarvis voice** plus the phrase cache.
  - The owner allowed changes to `~/jarvis-voice`, but another agent edits it too: build beside it.
- **Off limits:** the Jarvis HQ spec, GenUI kit and `DayFrameJarvis` package belong to a separate Codex project.

## Next steps, in order

1. **Ticket 10, fast Jarvis voice (Piper):** `.scratch/jarvis/issues/10-fast-jarvis-voice.md`.
   - The cloned OmniVoice server (127.0.0.1:5055) takes about 50 s per sentence.
   - Live replies now use the phrase cache (16 of 18 lines ready at 15:00) plus the best British Mac voice.
   - **Ask the owner before every download.**
2. **Chunk 2, presence and speed:**
   - Study Grok Bot's UX (ask before screen access).
   - A quick floating panel under the notch.
   - "Hey Jarvis" wake word.
   - The control socket + command registry, so Jarvis can operate its own UI (Herald's `os_ui`).
3. **Chunk 3, HQ pages:** Missions, Memory (Hermes + Briefing), Automations (Hermes cron + event triggers + Briefing automations), Connections (MCP, messaging), Usage.
4. **Chunk 4, Mac depth:** crash help, screen tools (OCR/QR/ask about a region), dictation, app installs, system monitor.

## Gotchas (each cost time today)

- **Another app is called "Jarvis":** Codex's Electron app at `~/Applications/Jarvis.app` (`local.jarvis.desktop`). Never `pkill -x Jarvis` or `pgrep -x Jarvis`; match `^/Applications/Jarvis.app/Contents/MacOS/Jarvis`.
- **Signing:** never change it (ADR 0002); the Screen Recording permission depends on it.
- **Recording pauses while the screen is locked,** by design. Check `CGSSessionScreenIsLocked` before suspecting a bug.
- **Island sounds** must stay on AVAudioPlayer. AVAudioPlayerNode crashed the app (SIGABRT) when the audio engine stopped on screen lock.
- **`hermes mcp add`** asks "Enable all N tools? [Y/n]" and cancels on a closed stdin: pipe `y`.
- **Disk:** free space swings 1–7 GB with swap. The build needs 3 GB (`df -h ~`).
- **Orphaned backends:** throwaway `hermes serve` test backends outlive their shell. Kill the ones whose ppid is 1, and never Jarvis's own (its parent is the Jarvis pid).
- **Hermes's installer** also added `ai.hermes.gateway` (a messaging gateway, unused, about 31 MB). It's left running; ask the owner before removing it.
- **Every change** needs a dated `CHANGELOG.md` entry and one commit; the pre-commit hook runs `./check.sh --staged`.
- **Saving a version:** tag + backup folder (`ditto` app zip + `git archive`) + bump `MARKETING_VERSION` / `CFBundleShortVersionString`. A GitHub push is blocked until the owner sets up `gh auth login`.
