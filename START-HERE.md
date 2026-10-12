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
| `App/` | The Mac app's source code (Xcode project, Swift) | Yes: looks, tabs, behavior |
| `App/Dayflow/` | The app's Swift files (folder name kept from the original) | Yes |
| `App/Dayflow.xcodeproj` | Open this in Xcode to browse or edit visually | Optional |
| `Briefing/` | The briefing service: daily briefings, memory, dashboard page, Clicky orb | Yes |
| `Briefing/briefing.py` | Briefing logic: what it writes, when, and which AI it talks to | Yes |
| `Briefing/dashboard.html` | The page shown in the Briefing tab | Yes |
| `Briefing/Companion.swift` | The Clicky orb | Yes |
| `Briefing/notes/` | Logs from the first install test | No |
| `tools/` | A small helper the app build needs | No |
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

## 2. Everyday commands

Run these in Terminal.

```bash
cd ~/Documents/Projects/Dayframe && ./build-and-install.sh          # rebuild + install + relaunch the app
cd ~/Documents/Projects/Dayframe && ./build-and-install.sh --build  # just check it still compiles
cd ~/Documents/Projects/Dayframe/Briefing && ./install.sh           # re-install Briefing after editing it
python3 ~/Briefing/app/briefing.py doctor                            # health check: what's working, what's not
python3 ~/Briefing/app/briefing.py brief --force                     # make a new briefing now
python3 ~/Briefing/app/briefing.py ask "what was I doing at 3pm?"    # ask your memory
```

**After installing a new app build,** macOS may ask you to allow Screen Recording again. The app is signed on this Mac, not by Apple. Adding a free Apple ID in Xcode (Settings → Accounts) would stop that.

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

### Tabs and screens
| Change | File | Where |
|---|---|---|
| Which **sidebar tabs** show, and their order | `App/Dayflow/Views/UI/MainView/SidebarView.swift` | `static let visible` (line 22) |
| What a tab shows | `App/Dayflow/Views/UI/MainView/Layout+Panels.swift` | `switch selectedIcon` (line ~66) |
| The **Briefing tab** (inside the app) | `App/Dayflow/Views/UI/BriefingPanelView.swift` | loads `http://127.0.0.1:8765` |
| What the **briefing page** looks like | `Briefing/dashboard.html` | one HTML file |
| First-run setup wording | `App/Dayflow/Views/Onboarding/LLMProviderSetupView.swift` | e.g. line ~210 |
| Turn the upstream GitHub-star and survey popups back on | `App/Dayflow/Utilities/Dayframe.swift` | `upstreamPrompts` |

### AI
| Change | File | Where |
|---|---|---|
| Model the app uses for screen analysis | In the app: Settings → Providers, or first-run setup | default set in `App/Dayflow/Core/AI/LocalModelPreset.swift` (`recommended`, line 20) |
| Qwen "thinking" off/on (off = fast) | `App/Dayflow/Core/AI/OllamaProvider+Networking.swift` | `reasoning_effort = "none"` (line ~72) |
| Model Briefing uses | `~/Briefing/config.json` | `"model": "qwen3.5:4b"` |
| Use LM Studio instead of Ollama for Briefing | `~/Briefing/config.json` | `"llm_backend": "openai"`, `"llm_url": "http://localhost:1234/v1"` |

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

- [ ] Merge the **Clicky orb** (`Briefing/Companion.swift`) into the app, so it's one app with one permission.
- [ ] Redesign `Briefing/dashboard.html` so it matches Dayframe and follows the palette inside the tab.
- [ ] New **app icon** and intro animation (the intro video still says "Dayflow").
- [ ] Remove the "How did you hear about us?" step from first-run setup.
- [ ] Optional: add a free Apple ID in Xcode so rebuilds stop asking for Screen Recording again.

## 7. Known issues

- Never run the old **Dayflow** app at the same time. Both use the same data folder.
- The build needs about 3 GB of free disk. The script checks first.
- One Briefing test (`test_code_candidate_from_model_goes_through_gate`) was already failing in the original zip. It isn't caused by Dayframe.
