# Dayframe: start here

Dayframe is your Mac app. It records your screen, turns it into a timeline, and gives you a daily briefing, all on your own Mac.

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
| `.scratch/` | Tickets: one folder per feature, one file per step, each with a `Status:` line | Yes |
| `App/` | The Mac app's source code (Xcode project, Swift) | Yes: looks, tabs, behavior |
| `App/Dayflow/` | The app's Swift files (folder name kept from the original) | Yes |
| `App/Dayflow.xcodeproj` | Open this in Xcode to browse or edit visually | Optional |
| `Briefing/` | The briefing service: daily briefings, memory, dashboard page, Clicky orb | Yes |
| `Briefing/briefing.py` | Briefing logic: what it writes, when, and which AI it talks to | Yes |
| `Briefing/dashboard.html` | The page shown in the Briefing tab | Yes |
| `Briefing/Companion.swift` | The Clicky orb | Yes |
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
| `/Applications/Dayframe.app` | The installed app (pinned to your Dock) |
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

### Start of day (opening animation, wallpaper, your day's apps)
Everything is in the app under **Settings → Start of day**. Code lives in `App/Dayflow/Welcome/`.
| Change | File | Where |
|---|---|---|
| The **opening animation** (spark, orbit, vortex, ignition, locks, logo, wordmark) | `Web/src/welcome/scene.ts` | `firstLaunch(T)` / `dailyWake(T)` say what is on screen at each second; `WelcomeScene` draws it. Preview: run the `dayframe-welcome` dev server, open `/welcome.html?variant=firstLaunch&palette=ember&t=2.6` for one frozen frame. Rebuild with `npm --prefix Web run build:welcome` (the build script does it too) |
| The **wordmark / tagline** text | `Web/src/welcome/welcome.html` | `#wordmark`, `#tagline` |
| The **sounds** (Aether Pulse masters, AAC) | `App/Dayflow/Welcome/Resources/welcome-*.m4a` | `first-launch` / `daily-wake`, `laptop` / `cinematic` mixes |
| **When** it plays (login once per session; unlock after N min away) | `App/Dayflow/Welcome/WelcomeController.swift` | `WelcomeLoginGate`, `WelcomeEventGate` (unit-tested in `WelcomeEventGateTests`) |
| The **wallpaper** look (sky, glow, dunes; no text) | `App/Dayflow/Welcome/WallpaperManager.swift` | `WallpaperArt`. Files go to `~/Library/Application Support/Dayframe/Wallpaper/` |
| What happens **after login** (Briefing, apps, layout, hide others) | `App/Dayflow/Welcome/StartOfDay.swift` | `run(reason:)`. Moving other apps' windows needs Accessibility, which you allow in System Settings |

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
| Which AI answers | The pills above the chat box: **Qwen** (default, on this Mac, free) · Codex · Claude. Your pick is remembered. |
| Qwen's chat prompt | `App/Dayflow/Core/AI/ChatPromptBuilder.swift` → `localSystemPrompt()` |
| How Qwen chat talks to Ollama (tool loop, streaming) | `App/Dayflow/Core/AI/OllamaProvider+DashboardChat.swift` |
| What the tools return to Qwen (one line per card, minutes, total, 6,000-char cap) | `App/Dayflow/Core/AI/DashboardChatTools.swift` → `compactResult` |
| When Chat unlocks | `App/Dayflow/Core/Access/FeatureAccessRequirements.swift` → `chatRequiredHours = 10` (Dayflow's original rule, kept on purpose) |

Ollama gives Qwen a 4,096-token window, so Qwen chat keeps the last 6 messages and gets compact tool results. Dayframe never asks Ollama for a bigger window, because that would reload the model and stall the timeline. Questions about one day work best; for a whole week, ask for a summary.

### Claude & ChatGPT (your own plans, no API keys)
| Change | Where |
|---|---|
| Sign in to Claude | Terminal: `claude`, then type `/login` (once) |
| Sign in to ChatGPT | Install once: `brew install codex`, then `codex login` |
| Which AI analyzes your screen (Claude / ChatGPT / Qwen) | In the app: **Settings → Providers** (primary + fallback) |
| Which AI writes your briefings | Briefing tab → **⋯** → "Briefings are written by", or `~/Briefing/config.json` → `"llm_backend": "claude_cli"` / `"codex_cli"` / `"ollama"` |
| Pick a specific Claude/ChatGPT model for briefings | `~/Briefing/config.json` → `"cli_model": ""` (blank = default) |
| See how much AI you've used | In the app: **Settings → Providers → AI usage** (links to the official "plan remaining" pages) |
| Code for this | `Briefing/briefing.py` → `cli_chat()`; app: `App/Dayflow/Core/AI/ClaudeProvider*.swift`, `CodexProvider*.swift`; usage: `App/Dayflow/Views/UI/Settings/AIUsageSection.swift` |

If Claude or ChatGPT fails (signed out, offline, limit hit), Briefing automatically falls back to Qwen on your Mac.

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
| App name and bundle ID | `App/Dayflow.xcodeproj/project.pbxproj`: `PRODUCT_NAME = Dayframe`, `PRODUCT_BUNDLE_IDENTIFIER = local.dayframe.app` |
| App icon | `App/Dayflow/Assets.xcassets/AppIcon.appiconset/` (still Dayflow's; to do) |
| Dock | Already pinned. To unpin: right-click the icon → Options → uncheck Keep in Dock |

---

## 4. What Dayframe changed from Dayflow

- **Renamed** to Dayframe everywhere you see text, with its own app ID. Your data folder is unchanged.
- **Removed:** usage analytics (PostHog), crash reporting (Sentry) and auto-updates (Sparkle), all deleted from the build. Stand-ins that do nothing are in `App/Dayflow/System/TelemetryStubs.swift`. Nothing is sent anywhere.
- **Removed:** the cloud AI options (Dayflow Pro, ChatGPT, Claude, Gemini, OpenRouter). Setup is local-only.
- **Removed:** the Flow waitlist, Agents and Support tabs, the launch video, and the GitHub-star and survey popups.
- **Fixed:** the Ollama "thinking bug". Qwen now answers in about 6 s instead of 20–46 s.
- **Added:** Qwen 3.5 4B as the default model (it can read screenshots).
- **Added:** six color palettes with an "ink spread" switch (Settings → Other → Colors).
- **Added:** a Briefing tab built into the sidebar.

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

---

## 6. To do

- [x] Window title and permission prompts say Dayframe.
- [ ] Merge the **Clicky orb** (`Briefing/Companion.swift`) into the app, so it's one app with one permission.
- [x] Briefing tab rebuilt natively in Dayflow's style (advanced pages still use `Briefing/dashboard.html`).
- [ ] New **app icon** (the intro video still says "Dayflow"). The opening animation is done (Start of day, Oct 12); the icon should reuse its ring mark.
- [x] "How did you hear about us?" step skipped in first-run setup.
- [x] Stable signing, so rebuilds keep the Screen Recording permission (section 7).
- [x] Chat uses Qwen on this Mac by default (Claude and Codex optional).

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
- The build needs about 3 GB of free disk. The script checks first.
- One Briefing test (`test_code_candidate_from_model_goes_through_gate`) was already failing in the original zip. It isn't caused by Dayframe.
- One app unit test (`OpenAICompatibleProviderTests.testCardRetryRetainsFullContextAndReturnsDetailedCards`) already fails in upstream Dayflow. Run the tests with `xcodebuild test -project App/Dayflow.xcodeproj -scheme Dayflow -derivedDataPath build -destination 'platform=macOS' -only-testing:DayflowTests`.
