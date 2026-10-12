# Dayframe change log

Every change to this project gets an entry here, so any person or AI can see what happened, when and why.

**Rules**
- Newest day first. Within a day, newest entry first.
- One entry per change. Time is local (Eastern), 24-hour.
- Every entry has: **What**, **Files**, **Why**, **Checked** (how it was verified). Add **Commit** when there is one.
- Keep entries short and factual. Bigger explanations go in `START-HERE.md`.
- A git hook blocks commits that don't include an update to this file (see 13:50 below).

Entry template:

```
### HH:MM: Short title
- **What:** …
- **Files:** …
- **Why:** …
- **Checked:** …
- **Commit:** …
```

---

## 2026-10-12 (Mon)

### 13:51: Recording always on + Dayflow Pro screen removed
- **What:**
  - New `RecordingWatchdog`: every 30 s, and 2–3 s after wake or unlock, it restarts recording if it stopped. Timed pauses are respected until they end; "pause indefinitely" is overridden. If macOS revoked the permission, it shows the permission notice (at most every 10 min).
  - Launch always turns recording on, ignoring a saved "off".
  - Launch-at-login is turned on once by default.
  - Settings no longer has the **Account** tab (Dayflow Pro sign-in, $20/$15 upgrade); Settings opens on Providers.
- **Files:** `App/Dayflow/App/RecordingWatchdog.swift` (new), `App/Dayflow/App/AppDelegate.swift`, `App/Dayflow/Views/UI/SettingsView.swift`
- **Why:**
  - The user said "the recording should always run no matter what".
  - The user asked to get rid of the Dayflow Pro upgrade screen.
- **Checked:**
  - Build passed.
  - Not yet installed: waiting for the user to create the "Dayframe Local" certificate, so the next install keeps its permission.
- **Commit:** see `git log`

### 13:50: Change log + stable signing for recording
- **What:** Added this `CHANGELOG.md` and a git pre-commit hook that requires it. `build-and-install.sh` now re-signs the app with a stable certificate ("Dayframe Local" or "Apple Development") when one exists.
- **Files:** `CHANGELOG.md`, `build-and-install.sh`, `.git/hooks/pre-commit`, `START-HERE.md`
- **Why:**
  - The user wants a dated log of every change.
  - **Resume did nothing:** `App/RecordingControl.swift` silently ignores Resume when the Screen Recording permission is invalid. Each ad-hoc build gets a new code hash, so macOS's old grant stopped matching.
- **Checked:**
  - Script syntax OK (`bash -n`).
  - The signature was confirmed as hash-based (`codesign -dr -` showed `cdhash`).
  - No certificate exists yet; the user needs to create one (see START-HERE "Recording won't resume").
- **Commit:** see `git log`

### 13:43: Guide updated for v2
- **What:** `START-HERE.md` gained sections for the native Briefing tab, Claude/ChatGPT via your own plans, and AI usage.
- **Files:** `START-HERE.md`
- **Why:** Keep the guide in step with the app.
- **Checked:** Read through.
- **Commit:** `dbcd489`

### 13:41: Briefing tab fixes
- **What:**
  - The Briefing data decoder now tolerates "note" entries that have no start time, and skips any malformed item instead of failing.
  - Long text wraps.
  - The remaining user-visible "Dayflow" strings were renamed to Dayframe (33 more).
- **Files:** `App/Dayflow/Views/UI/Briefing/BriefingService.swift`, `BriefingView.swift`, plus 33 strings across `App/Dayflow`
- **Why:** The tab was falling back to the web page because one null field broke decoding.
- **Checked:**
  - Decoded live `/api/state` with a standalone test (5 timeline items, 2 to-dos, sections parsed).
  - The tab rendered in the app (screenshot).
- **Commit:** `9f0ba15`

### 13:33: Claude & ChatGPT through your own plans (no API keys)
- **What:**
  - Re-enabled Dayflow's Claude Code and Codex CLI providers in onboarding and Settings. Removed Dayflow Pro, Gemini and OpenRouter.
  - Briefing gained `llm_backend` values `claude_cli` and `codex_cli`, falling back to Qwen when they fail.
  - New Settings › Providers › **AI usage** section: calls and tokens per provider, plus links to the official plan-usage pages.
- **Files:**
  - `App/Dayflow/Views/Onboarding/Prototype/OnboardingPrototypeChooseProviderStep.swift`
  - `App/Dayflow/Views/UI/Settings/ProvidersSettingsViewModel.swift`
  - `App/Dayflow/Views/UI/Settings/AIUsageSection.swift` (new)
  - `App/Dayflow/Views/UI/Settings/SettingsProvidersTabView.swift`
  - `Briefing/briefing.py` (`cli_chat()`)
  - `Briefing/tests/test_cli_backend.py` (new)
- **Why:** The user has Claude and ChatGPT subscriptions and wants no API keys. They chose "Everything", so screenshots are included.
- **Checked:**
  - 5 new tests pass; the full suite is 86/87 (the one failure was already in the original zip).
  - The real `claude` CLI returned "OAuth session expired", so the user must run `claude` then `/login`.
  - The Qwen fallback answered.
  - Deployed to `~/Briefing/app` and restarted the dashboard agent.
- **Commit:** `ec61652`

### 13:24: Native Briefing screen
- **What:** Rebuilt the Briefing tab in SwiftUI using Daily's parts.
  - Sections: Where you left off, Your next thing (with goal pill), Open loops (check off / add), Today so far, This week, Ask your past.
  - A **⋯** menu opens the advanced web pages and sets who writes briefings.
- **Files:**
  - `App/Dayflow/Views/UI/Briefing/BriefingService.swift` (new)
  - `App/Dayflow/Views/UI/Briefing/BriefingView.swift` (new)
  - `App/Dayflow/Views/UI/BriefingPanelView.swift` (`tab` parameter)
  - `App/Dayflow/Views/UI/MainView/Layout+Panels.swift`
- **Why:** The user wants Briefing to look and feel like Timeline and Daily.
- **Checked:** Build passed; screenshot in the app with real data; "New briefing" button works.
- **Commit:** `733ed52`

### 13:09: Project organized into one folder
- **What:**
  - New layout: `App/` (was `Dayflow/`), `Briefing/` (moved in from `~/Desktop/dayflow-test/dayflow-briefing`), `tools/`, `Upstream/` (unused upstream docs and scripts).
  - Added `START-HERE.md` and `build-and-install.sh`.
- **Files:** whole repo layout
- **Why:** The user wants one organized place to find and change anything.
- **Checked:** `./build-and-install.sh --build` passed from the new layout.
- **Commit:** `431b0fe`

### 13:00: Onboarding offers Ollama + Qwen 3.5
- **What:**
  - Added a "Use Ollama + Qwen 3.5" button and an Ollama option in the engine picker.
  - Install text now says Qwen 3.5.
  - The thinking fix applies to any `:11434` endpoint.
- **Files:** `App/Dayflow/Views/Onboarding/LLMProviderSetupView.swift`, `App/Dayflow/Core/AI/OllamaProvider+Networking.swift`
- **Why:** Upstream onboarding only offered LM Studio or Custom.
- **Checked:** The connection test passed in the app with `qwen3.5:4b`.
- **Commit:** `dcf0a38`

### 12:57: Color palettes, Briefing tab, Dayframe naming
- **What:**
  - Six palettes (Original, Lagoon, Lavender, Matcha, Rose, Ember) with an ink-spread reveal; picker under Settings › Other › Colors.
  - First Briefing tab (web view).
  - "Dayflow" renamed in display strings (95).
  - Launch video and the upstream GitHub-star and survey prompts removed.
- **Files:**
  - `App/Dayflow/Utilities/DayframePalette.swift` (new)
  - `App/Dayflow/Utilities/Dayframe.swift` (new)
  - `App/Dayflow/Utilities/DayflowTheme.swift`
  - `App/Dayflow/App/DayflowApp.swift`
  - `App/Dayflow/Views/UI/BriefingPanelView.swift` (new)
  - `App/Dayflow/Views/UI/MainView/SidebarView.swift`
  - `App/Dayflow/Views/UI/Settings/SettingsOtherTabView.swift`
- **Why:** The user likes the original colors but wants a fun switcher, Briefing built in, and their own name on the app.
- **Checked:** Build passed; installed.
- **Commit:** `6dce9e9`

### 12:44: Fork turned into Dayframe
- **What:**
  - New bundle ID `local.dayframe.app` and name Dayframe.
  - Removed Sentry, PostHog and Sparkle (no-op stand-ins in `System/TelemetryStubs.swift`).
  - Local-only providers; Qwen 3.5 4B preset; `reasoning_effort:"none"` so Qwen doesn't "think" (6 s instead of 20–46 s).
  - Sidebar trimmed (no Flow, Agents or Support).
- **Files:**
  - `App/Dayflow.xcodeproj/project.pbxproj`
  - `App/Dayflow/System/TelemetryStubs.swift` (new)
  - `App/Dayflow/Utilities/SentryHelper.swift`
  - `App/Dayflow/System/UpdaterManager.swift`
  - `App/Dayflow/Core/AI/OllamaProvider+Networking.swift`
  - `App/Dayflow/Core/AI/LocalModelPreset.swift`
  - `App/Dayflow/Info.plist`
  - `App/Dayflow/Dayflow.entitlements`
- **Why:** The user's own app, private, no third-party telemetry.
- **Checked:**
  - Build passed after freeing disk; the Sentry download had filled it twice.
  - Thinking fix measured with curl against Ollama.
- **Commit:** `54cdb95`

### 12:33: Upstream baseline
- **What:** Shallow clone of Dayflow v2.6.0 (github.com/JerryZLiu/Dayflow, commit a45c7be, MIT) as the first commit.
- **Files:** everything
- **Why:** Start from the real source rather than decompiling. Always comparable to the original.
- **Checked:** n/a
- **Commit:** `1df9be4`

### 11:45: (before the fork) Dayflow Briefing zip installed
- **What:** Installed the Briefing add-on from `~/Downloads/dayflow-briefing.zip` into `~/Briefing`, using model `qwen3.5:4b`, and ran the first `doctor`.
- **Files:** `~/Briefing/*`, LaunchAgents `com.dayflowbriefing.*`
- **Why:** The user's first test run of the add-on.
- **Checked:**
  - `doctor` results are saved in `Briefing/notes/first-doctor.txt`.
  - Fixed a permissions bug: `install.sh` ran chmod before building the companion.
- **Commit:** none (before the repo existed)
