# Jarvis (formerly Dayframe): start here

Jarvis is your Mac app and your chief-of-staff agent. It records your screen, turns it into a timeline, gives you a daily briefing, and (since 2026-10-14) acts on your Mac for you through **Hermes Agent** with the system tools from **Herald OS**. The rename is display only: the project folder, bundle ID (`local.dayframe.app`), `dayframe://` links, settings keys and data folder keep the Dayframe name.

**Picking Jarvis up? Read `docs/jarvis/HANDOFF.md` first.**

**Jarvis in one paragraph:** the Jarvis tab (first in the sidebar) is the HQ. Swift starts `hermes serve` (`App/Dayflow/Core/Jarvis/HermesBackend.swift`), the page (`Web/src/jarvis`, bundled as `App/Dayflow/Jarvis/Resources/jarvis.html`) talks to it over a WebSocket, system actions go through the vendored plugin in `Jarvis/bridge/` (approval cards for anything that changes something), ⌥Space talks, and answers to voice turns are spoken from the phrase cache, then Alan the fast Piper filler (`~/jarvis-piper`, port 5056), then the Mac's British voice. The slow cloned voice stays on `~/jarvis-voice`, port 5055, for notices and for filling that cache. The Herald OS study and capability map are in `docs/jarvis/HERALD-MAP.md`; tickets in `.scratch/jarvis/`.

It's built from **Dayflow** (MIT license, © 2025 Jerry Liu, github.com/JerryZLiu/Dayflow) plus your **Briefing** add-on.

Everything lives in this one folder: `~/Documents/Projects/Dayframe`.

---

## 1. What's in this folder

| Folder / file | What it is | Do you edit it? |
|---|---|---|
| `START-HERE.md` | This guide | Yes, keep notes here |
| `build-and-install.sh` | One command to rebuild the app and put it in Applications | Just run it |
| `check.sh` | The clean-code gate every change must pass (style, types, tests) | Just run it |
| `logs.sh` | Shows Dayframe's own log lines (why the welcome did or didn't play, etc.) | Just run it |
| `AGENTS.md` | How any AI (Claude, Grok, Codex) must work here: the loop, standards, guardrails. `CLAUDE.md` points to it | Rarely |
| `CONTEXT.md` | The glossary: the one word for each thing (card, show, welcome, slot…) | When a new idea needs a name |
| `docs/adr/` | Short records of decisions that are hard to undo, and why they were made | When making one |
| `docs/audits/` | Evidence-driven audit logs, recommendations, and handoff summaries | On audit runs |
| `.scratch/` | Tickets: one folder per feature, one file per step, each with a `Status:` line | Yes |
| `App/` | The Mac app's source code (Xcode project, Swift) | Yes: looks, tabs, behavior |
| `App/Dayflow/` | The app's Swift files (folder name kept from the original) | Yes |
| `App/Dayflow.xcodeproj` | Open this in Xcode to browse or edit visually | Optional |
| `Web/` | The web pages inside the app: the React Briefing, the notch island show, the opening animation, the UI-kit gallery (`kit.html`). The build script builds them | Yes |
| `Jarvis/` | Jarvis's system-tools plugin for Hermes (`bridge/`, vendored from Herald OS; what changed is in `bridge/JARVIS-CHANGES.md`) and `install-bridge.sh`, which links it into Hermes (`--undo`, `--test`) | Yes |
| `Briefing/` | The briefing service: daily briefings, memory, dashboard page | Yes |
| `Briefing/briefing.py` | Briefing logic: what it writes, when, and which AI it talks to | Yes |
| `Briefing/dashboard.html` | The page shown in the Briefing tab's advanced views | Yes |
| `Briefing/notes/` | Logs from the first install test | No |
| `tools/` | A small helper the app build needs | No |
| `Keepalive/` | Background job that reopens Dayframe and Ollama if they ever stop (installed by the build script) | Rarely |
| `Upstream/` | Dayflow's original docs and release scripts; not used by Dayframe | No |
| `build/` | Build output (safe to delete; recreated on the next build) | No |
| `LICENSE` | Dayflow's MIT license. **Keep this file**; the license requires it | No |

### Things that live outside this folder

These are created when the app runs, so leave them where they are.

| Location | What |
|---|---|
| `/Applications/Jarvis.app` | The installed app (pinned to your Dock; it was `Dayframe.app` until 2026-10-14) |
| `~/.hermes/` | Hermes Agent: its install (`hermes-agent/`), config, memories, sessions and sign-ins. Jarvis's audit log and permission policy are in `~/.hermes/herald-os/` |
| `~/jarvis-voice/` | The cloned Jarvis voice (OmniVoice, `127.0.0.1:5055`, LaunchAgent `local.jarvis.tts`). Slow; used for notices and the phrase cache |
| `~/jarvis-piper/` | Alan, the fast filler voice (Piper, `127.0.0.1:5056`, LaunchAgent `local.jarvis.piper`). Outside this project on purpose, so Hermes does not read ~/Documents |
| `~/Library/Application Support/Dayflow/` | Your recordings and timeline database. The name stays "Dayflow" on purpose, so Briefing can read it |
| `~/Briefing/` | The *installed* copy of Briefing: `app/`, your memory notes (`memory/`), settings (`config.json`) and logs |
| `~/Library/LaunchAgents/com.dayflowbriefing.*` | The background jobs that run Briefing on a schedule |
| Ollama + `qwen3.5:4b` | The AI model everything uses (`localhost:11434`) |

---

## Change log (read this first if you're an AI picking up the project)

`CHANGELOG.md` records every change with date, time, what, files, why and how it was checked. Newest is first. **Add an entry for every change.** The rules for AIs working here are in `AGENTS.md`.

Every commit goes through `.githooks/pre-commit`, which runs `./check.sh --staged`. The commit is refused unless today's CHANGELOG entry has What/Files/Why/Checked, no Swift file gained swift-format warnings, and the web and Briefing checks and tests pass for what changed. After a fresh clone, turn the hook on once with `git config core.hooksPath .githooks`.

---

## 2. Everyday commands

Run these in Terminal.

```bash
cd ~/Documents/Projects/Dayframe && ./build-and-install.sh          # rebuild + install + relaunch the app
cd ~/Documents/Projects/Dayframe && ./build-and-install.sh --build  # just check it still compiles
cd ~/Documents/Projects/Dayframe && ./check.sh                      # is everything clean? (add --app to also build + run the unit tests)
cd ~/Documents/Projects/Dayframe && ./logs.sh 1h welcome            # what Dayframe logged in the last hour (one area, or leave it off for all)
cd ~/Documents/Projects/Dayframe/Briefing && ./install.sh           # re-install Briefing after editing it
python3 ~/Briefing/app/briefing.py doctor                            # health check: what's working, what's not
python3 ~/Briefing/app/briefing.py brief --force                     # make a new briefing now
python3 ~/Briefing/app/briefing.py ask "what was I doing at 3pm?"    # ask your memory
```

**After installing a new app build,** recording keeps working: every build has the same signature, so macOS keeps the Screen Recording permission (see section 7).

---

## 3. "I want to change…" → where to go

All paths below are relative to this folder. After editing anything in `App/`, run `./build-and-install.sh`. After editing anything in `Briefing/`, run `Briefing/install.sh`.

### Look and feel
| Change | File | Where |
|---|---|---|
| Add or edit a **color palette** (background glow, accent, buttons) | `App/Dayflow/Utilities/DayframePalette.swift` | `spec` (line ~62): one block per palette with hex colors. To add one, add a `case` at the top plus a `Spec` block |
| The **color-switch animation** (speed, style) | same file | `PaletteRevealOverlay`, `withAnimation(.easeInOut(duration: 0.75))` (line ~222) |
| Where the **color picker** appears | `App/Dayflow/Views/UI/Settings/SettingsOtherTabView.swift` | `colorsSection` (line ~20) |
| The **Original** colors themselves | `App/Dayflow/Utilities/DayflowTheme.swift` | `lightPalette` and the dark palette (e.g. `accent: Color(hex: "F3854B")`, line ~286) |
| Light/Dark mode | In the app: Settings → Other → Light/Dark mode | none |

### Briefing messages in the notch (briefing, check-in, nudges)
Briefing no longer pops up macOS dialogs. It leaves a message in `~/Briefing/notices/` and opens `dayframe://notice?id=…`; the pill peeks one line under the notch, then the eyes turn the accent colour until you read it. Hover to peek again, click for the card. If Dayframe doesn't answer within 3 s (not running, island off), Briefing shows its old dialog instead.
| Change | File | Where |
|---|---|---|
| The **card and peek** look (layout, copy, buttons) | `App/Dayflow/Island/NotchPillView.swift` | `NoticeCard`, `peekRow`, `NotchPillLayout` |
| **How long** it peeks, queueing, expiry | `App/Dayflow/Island/IslandController.swift` | `presentNotice`, `showNextNotice` |
| The **hand-off files** and answer format | `App/Dayflow/Island/BriefingNotice.swift` and `Briefing/briefing.py` `notch()` | `BriefingNoticeInbox` |
| What the briefing **says when the AI is down** | `Briefing/briefing.py` | `fallback_brief()` |

### Start of day (opening animation, wallpaper, your day's apps)
Everything is in the app under **Settings → Start of day**. Code lives in `App/Dayflow/Welcome/`.
| Change | File | Where |
|---|---|---|
| The **opening animation** (spark, orbit, vortex, ignition, locks, logo, wordmark) | `Web/src/welcome/scene.ts` | `firstLaunch(T)` / `dailyWake(T)` say what is on screen at each second; `WelcomeScene` draws it. Preview: run the `dayframe-welcome` dev server, open `/welcome.html?variant=firstLaunch&palette=ember&t=2.6` for one frozen frame. Rebuild with `npm --prefix Web run build:welcome` (the build script does it too) |
| The **wordmark / tagline** text | `Web/src/welcome/welcome.html` | `#wordmark`, `#tagline` |
| The **sounds** (Aether Pulse masters, AAC) | `App/Dayflow/Welcome/Resources/welcome-*.m4a` | `first-launch` / `daily-wake`, `laptop` / `cinematic` mixes |
| **When** it plays (login once per session; unlock after N min away) | `App/Dayflow/Welcome/WelcomeController.swift` | `WelcomeLoginGate`, `WelcomeEventGate` (unit-tested in `StartOfDayTests`) |
| The **wallpaper** look (sky, glow, dunes; no text) | `App/Dayflow/Welcome/WallpaperManager.swift` | `WallpaperArt`. Files go to `~/Library/Application Support/Dayframe/Wallpaper/` |
| What happens **after login** (Briefing, apps, layout, hide others) | `App/Dayflow/Welcome/StartOfDay.swift` | `run(reason:)`. Moving other apps' windows needs Accessibility, which you allow in System Settings |
| Turn on a **Focus** at start of day | In the app: Settings → Start of day → Focus. Code: `App/Dayflow/Welcome/FocusShortcut.swift` | macOS has no Focus API, so it runs a Shortcut you make once (Set Focus → Work → On) |
| The **Today's apps** row on Briefing (click to open, "Set up my day") | `Web/src/briefing/briefing-page.tsx` (`TodaysApps`) and `BriefingView.swift` (`todaysApps`) | It only opens apps on your Start of day list |

### Tabs and screens
| Change | File | Where |
|---|---|---|
| Which **sidebar tabs** show, and their order | `App/Dayflow/Views/UI/MainView/SidebarView.swift` | `static let visible` (line 22) |
| What a tab shows | `App/Dayflow/Views/UI/MainView/Layout+Panels.swift` | `switch selectedIcon` (line ~66) |
| The **Briefing tab** (native screen: cards, next thing, loops, today, focus, ask) | `App/Dayflow/Views/UI/Briefing/BriefingView.swift` | one section per `private var …Card` |
| How the Briefing tab talks to your briefing service | `App/Dayflow/Views/UI/Briefing/BriefingService.swift` | refresh every 2 min; `/api/state`, `/api/brief`, `/api/todo`, `/api/ask` |
| The advanced pages under **⋯ More** (Memory, Projects, Weekly, Automations, Settings) | `Briefing/dashboard.html` (opened by `App/Dayflow/Views/UI/BriefingPanelView.swift`) | one HTML file |
| First-run setup wording | `App/Dayflow/Views/Onboarding/LLMProviderSetupView.swift` | e.g. line ~210 |
| Turn the upstream GitHub-star and survey popups back on | `App/Dayflow/Utilities/Dayframe.swift` | `upstreamPrompts` |

### AI
| Change | File | Where |
|---|---|---|
| Model the app uses for screen analysis | In the app: Settings → Providers, or first-run setup | default set in `App/Dayflow/Core/AI/LocalModelPreset.swift` (`recommended`, line 20) |
| Qwen "thinking" off/on (off = fast) | `App/Dayflow/Core/AI/OllamaProvider+Networking.swift` | `reasoning_effort = "none"` (line ~72) |
| Model Briefing uses | `~/Briefing/config.json` | `"model": "qwen3.5:4b"` |
| Use LM Studio instead of Ollama for Briefing | `~/Briefing/config.json` | `"llm_backend": "openai"`, `"llm_url": "http://localhost:1234/v1"` |

### Chat (ask about your day)
| Change | Where |
|---|---|
| Which AI answers | The pills above the chat box: **Qwen** (default, on this Mac, free) · Codex · Claude · Grok. Your pick is remembered. |
| Qwen's chat prompt | `App/Dayflow/Core/AI/ChatPromptBuilder.swift` → `localSystemPrompt()` |
| How Qwen chat talks to Ollama (tool loop, streaming) | `App/Dayflow/Core/AI/OllamaProvider+DashboardChat.swift` |
| What the tools return to Qwen (one line per card, minutes, total, 6,000-char cap) | `App/Dayflow/Core/AI/DashboardChatTools.swift` → `compactResult` |
| When Chat unlocks | `App/Dayflow/Core/Access/FeatureAccessRequirements.swift` → `chatRequiredHours = 10` (Dayflow's original rule, kept on purpose) |

Ollama gives Qwen a 4,096-token window, so Qwen chat keeps the last 6 messages and gets compact tool results. Dayframe never asks Ollama for a bigger window, because that would reload the model and stall the timeline. Questions about one day work best; for a whole week, ask for a summary.

### Claude, ChatGPT & Grok (your own plans, no API keys)
| Change | Where |
|---|---|
| Sign in to Claude | Terminal: `claude`, then type `/login` (once) |
| Sign in to ChatGPT | Install once: `brew install codex`, then `codex login` |
| Sign in to Grok | Terminal: `~/.grok/bin/grok login` (once), then Settings → Providers → Grok → Test |
| Which AI analyzes your screen (Claude / ChatGPT / Grok / Qwen) | In the app: **Settings → Providers** (primary + fallback). Grok reads the screenshots' on-screen text, not the images |
| Which AI writes your briefings | Briefing tab → **⋯** → "Briefings are written by", or `~/Briefing/config.json` → `"llm_backend": "claude_cli"` / `"codex_cli"` / `"grok_cli"` / `"ollama"` |
| Let Grok read your Dayframe data (MCP) | Settings → MCP / CLI → Grok CLI → Connect. The Grok Bot desktop app can't take local MCP servers yet |
| Pick a specific Claude/ChatGPT model for briefings | `~/Briefing/config.json` → `"cli_model": ""` (blank = default) |
| See how much AI you've used | In the app: **Settings → Providers → AI usage** (links to the official "plan remaining" pages) |
| Code for this | `Briefing/briefing.py` → `cli_chat()`; app: `App/Dayflow/Core/AI/ClaudeProvider*.swift`, `CodexProvider*.swift`, `GrokCLI.swift`, `GrokProvider*.swift`, shared `AgentCLISupport*.swift`; usage: `App/Dayflow/Views/UI/Settings/AIUsageSection.swift` |

If Claude, ChatGPT or Grok fails (signed out, offline, limit hit), Briefing automatically falls back to Qwen on your Mac.

### Briefing schedule and behavior (no rebuild needed)
Edit `~/Briefing/config.json`. Changes apply on the next run.

| Change | Setting |
|---|---|
| Evening debrief time | `"debrief_hour": 18` |
| No check-ins during these hours | `"checkin_quiet_hours": [22, 8]` |
| Speak briefings out loud | `"speak": true` |
| Hide apps, sites or words from memory | `"blocklist": {"apps": [], "sites": [], "keywords": []}` |
| Delete old recordings after they're summarized | `"cleanup_enabled": true` (dry run until you set this) |
| How often check-ins and distills run | `Briefing/install.sh`: `StartInterval` 4500 (check-in) and 1800 (distill), in seconds; re-run `install.sh` |

### App identity
| Change | File |
|---|---|
| App name and bundle ID | `App/Dayflow.xcodeproj/project.pbxproj`: `PRODUCT_NAME = Jarvis`, `PRODUCT_BUNDLE_IDENTIFIER = local.dayframe.app` (the bundle ID never changes: Screen Recording permission depends on it) |
| App icon (the eclipse ring from the opening animation) | Drawn by `App/Dayflow/Welcome/AppIconArt.swift`. The Dock redraws it in your palette while Dayframe runs (`AppIconManager`). The bundled PNGs in `App/Dayflow/Assets.xcassets/AppIcon.appiconset/` come from `AppIconTests.testWriteBundledAppIcon` (see CHANGELOG 2026-10-13 13:51). If the Dock shows an old icon: `killall Dock` |
| Dock | Already pinned. To unpin: right-click the icon → Options → uncheck Keep in Dock |

---

## 4. What Dayframe changed from Dayflow

- **Renamed** to Dayframe everywhere you see text, with its own app ID. Your data folder is unchanged.
- **Removed:** usage analytics (PostHog), crash reporting (Sentry) and auto-updates (Sparkle), all deleted from the build. Stand-ins that do nothing are in `App/Dayflow/System/TelemetryStubs.swift`. Nothing is sent anywhere.
- **Removed:** the paid cloud options (Dayflow Pro, Gemini, OpenRouter). AI runs on Qwen on this Mac, or on your own Claude / ChatGPT / Grok plans through their command-line tools. No API keys.
- **Removed:** the Flow waitlist, Agents and Support tabs, the launch video, and the GitHub-star and survey popups.
- **Fixed:** the Ollama "thinking bug". Qwen now answers in about 6 s instead of 20–46 s.
- **Added:** Qwen 3.5 4B as the default model (it can read screenshots).
- **Added:** six color palettes with an "ink spread" switch (Settings → Other → Colors).
- **Added:** a Briefing tab (React page, with a native fallback) and Chat on Qwen.
- **Added:** the notch island: a pill around the notch and a welcome-back show (Settings → Other → Notch island).
- **Added:** Briefing's messages come out of the notch as a quiet peek instead of macOS dialogs.
- **Added:** Start of day: the opening animation, wallpaper, your day's apps, an optional Focus.
- **Added:** Grok as a fourth AI, and the eclipse-ring app icon.
- **Added:** recording safeguards (section 7).

See every change with:

```bash
git -C ~/Documents/Projects/Dayframe log --stat
```

---

## 5. Undo anything

The whole folder is one git repository. Every change was saved as a commit.

```bash
git -C ~/Documents/Projects/Dayframe log --oneline     # list of saved versions
git -C ~/Documents/Projects/Dayframe diff               # what changed since the last save
git -C ~/Documents/Projects/Dayframe checkout -- <file> # throw away unsaved edits to one file
```

The first commit is the untouched Dayflow v2.6.0, so you can always compare against the original.

### Saved versions

Each finished version gets a git tag, a backup copy, and a push to GitHub.

| Version | Date | What it is |
|---|---|---|
| `v1.0` | 2026-10-13 | Grok, the ring icon, Start of day with Focus and Today's apps, the notch island, the React Briefing |
| `v1.1` | 2026-10-13 | v1.0 plus the v2 audit fixes: Briefing installer works again without the Companion, never reinstalls Dayflow, Qwen3.5 upgrade sheet, dashboard backend picker |
| `v1.2` | 2026-10-13 | v1.1 plus Briefing's messages from the notch (quiet peek instead of dialogs) and a sharper briefing when the AI is busy |
| `v1.3` | 2026-10-14 | v1.2 plus (app now shows v1.3) the notch Resume card & non-starving notice queue, sandbox-hermetic Briefing tests, Evolution Center (L0/L1/L2 pipeline & state machine), and `docs/app-evolution/` |
| `v1.4` | 2026-10-14 | **Jarvis** (renamed from Dayframe, display only): Hermes Agent on Grok 4.6, the Jarvis tab (HQ) with tools and approval cards, Herald OS system tools, timeline via MCP, ⌥Space with spoken summaries, phrase cache in the Jarvis voice, island-sound crash fix |

- **List them:** `git -C ~/Documents/Projects/Dayframe tag -n`
- **Look at one** (read-only): `git -C ~/Documents/Projects/Dayframe checkout v1.0`. Come back with `git -C ~/Documents/Projects/Dayframe checkout main`.
- **Backup copies:** `~/Documents/Projects/Dayframe Versions/<version>/`. Each holds `Dayframe.app.zip` (the installed app, signature kept: unzip and drag to Applications) and `Dayframe-source.zip` (the code at that tag).

---

## 6. To do

**Only you can do these** (Jarvis is waiting on them):
- [x] Grok signed in to Hermes (2026-10-14); default model `xai-oauth` / `grok-4.6`.
- [ ] Optional brains: `hermes auth add openai-codex` (ChatGPT), `hermes auth add anthropic --type oauth` (Claude).
- [ ] Allow the microphone the first time you press ⌥Space, and try a real voice turn.
- [ ] Optional: download a better instant voice (System Settings › Accessibility › Spoken Content › System voice › Manage Voices: Jamie (Premium) or Daniel (Enhanced)).
- [ ] Decide what to do about the name clash: Codex's separate Electron app is also called "Jarvis" (`~/Applications/Jarvis.app`, `local.jarvis.desktop`).
- [ ] Sign in to Grok: `~/.grok/bin/grok login`. Then Settings → Providers → Grok → Test, and Settings → MCP / CLI → Grok CLI → Connect.
- [ ] In Shortcuts, make "Work Focus" (Set Focus → Work → On). Then pick it in Settings → Start of day → Focus.
- [ ] Add your day's apps: Settings → Start of day → Add app…
- [ ] Allow Accessibility for Dayframe (System Settings → Privacy & Security → Accessibility), so Start of day can place windows.
- [ ] Test the real triggers: log out and back in (opening animation), and lock the Mac for 10+ minutes (daily wake and the welcome-back show).
- [ ] Save the design system: in a terminal `claude` session in `Web/`, run `/design-login`, then `/design-sync Dayframe Design System`.

**For an AI session** (tickets in `.scratch/`):
- [ ] **Next for Jarvis:** try a real ⌥Space turn with Alan (ticket `.scratch/jarvis/issues/10-fast-jarvis-voice.md` stays open; training a Jarvis Piper voice is deferred). Then chunk 2 (quick panel, "Hey Jarvis", control socket). Plan: `~/.claude/plans/okay-now-that-we-swift-lovelace.md`.
- [ ] After `grok login`: test whether Grok accepts screenshots, not just their text (`.scratch/grok/issues/05-grok-images.md`).
- [ ] The first-run intro video still says "Dayflow".

**Done:**
- [x] Window title and permission prompts say Dayframe.
- [x] Briefing tab rebuilt (React page plus native fallback; advanced pages still use `Briefing/dashboard.html`).
- [x] New app icon: the opening animation's eclipse ring (2026-10-13).
- [x] "How did you hear about us?" step skipped in first-run setup.
- [x] Stable signing, so rebuilds keep the Screen Recording permission (section 7).
- [x] Chat uses Qwen on this Mac by default (Claude, Codex and Grok optional).
- [x] Companion orb retired and removed at owner request (2026-10-13).

## 7. Recording: how it stays on (and what to do if it ever stops)

Recording is always on, like Dayflow: a screenshot every 10 s goes into 10-minute videos in `~/Library/Application Support/Dayflow/recordings`. Every 15 minutes Qwen turns them into timeline cards.

**What keeps it running (added 2026-10-12, after a 1-hour silent outage):**

| Safeguard | What it does |
|---|---|
| Stable signing (`build-and-install.sh`) | Every build is signed ad-hoc with the same identity (`identifier "local.dayframe.app"`), so macOS keeps the Screen Recording permission. The build **fails** if this ever changes. Don't change how the app is signed. |
| Watchdog (`App/RecordingWatchdog.swift`) | Every 30 s and after wake/unlock: restarts recording if it's off, and restarts capture if no frame was saved for 3+ min while you're at the Mac. |
| Permission alerts | If macOS blocks recording: an in-app notice (with **Restart Dayframe** and **Reset permission**) plus a Mac notification "Dayframe isn't recording" (at most hourly). |
| Keep-alive (`Keepalive/`) | A LaunchAgent reopens Dayframe and Ollama within 2 minutes if either isn't running. To turn it off: `launchctl bootout gui/$(id -u)/local.dayframe.keepalive` |
| Batch recovery (`AnalysisManager`) | Batches cut off by a quit or crash re-run at the next launch. One batch at a time, with a 5-minute AI timeout. |
| Clean quit | Rebuilds and quits close the current video first, so no minutes are lost. |
| Health check | `python3 ~/Briefing/app/briefing.py doctor` shows `recorder` as an error if no frame was saved for 15+ minutes. |

**If you ever see "Dayframe isn't recording":** click the notification, or the notice's **Reset permission**, then allow Dayframe and click **Restart Dayframe**. The same fix in Terminal:

```bash
tccutil reset ScreenCapture local.dayframe.app
```

Then reopen Dayframe and click Allow. Turning the switch off and on in System Settings does **not** fix a signature mismatch; the reset does.

**Quick check that it's recording:** the newest frame should be seconds old.

```bash
sqlite3 ~/Library/Application\ Support/Dayflow/chunks.sqlite "select datetime(max(captured_at),'unixepoch','localtime') from screenshots"
```

---

## 8. Known issues

- Never run the old **Dayflow** app at the same time. Both use the same data folder.
- The build needs about 3000 MB of free disk (or `DAYFRAME_LOW_DISK_OK=1` with 1000+ MB free for incremental builds). The script checks first. `build/` is only build output: deleting it frees about 1.4 GB, and the next build recreates it (the first build after that is slower).
- All tests pass (as of 2026-10-13: 251 app, 95 Briefing, 24 web). Run them all with `./check.sh --app`. The two failures inherited from Dayflow and the Briefing zip were fixed on 2026-10-13 (CHANGELOG, commit c874439).
