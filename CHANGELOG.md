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

### 14:38: Guide updated for the recording safeguards
- **What:**
  - `START-HERE.md` section 7 is rewritten as "Recording: how it stays on". It has a table of every safeguard, the one-line fix if recording is ever blocked, and a check that recording is live.
  - Added `Keepalive/` to the folder table.
  - Ticked off the done to-dos: window title, referral step, stable signing.
  - Noted the upstream unit test that already fails, and how to run the tests.
  - The "Dayframe Local" certificate steps were removed; the certificate isn't used anymore.
- **Files:** `START-HERE.md`
- **Why:** So the user, or any AI picking this up, knows what keeps recording on and what not to change (signing).
- **Checked:**
  - Read through.
  - Batch 1 (11:53–12:08, the old "Processing failed" card) completed on Retry. Every batch today is now completed or skipped-short.
  - The only gap left is 13:34–14:23, when nothing was recorded.
- **Commit:** see `git log`

### 14:37: Whole-app audit: dead ends from removed Dayflow features fixed
- **What:** An audit traced every menu item, tab, Settings control and onboarding step. Everything broken by the earlier removals was fixed:
  - **Chat:** the Gemini chip is removed. It defaults to Claude, and a stored "gemini" falls back to Claude. The locked screen says to install Claude Code (`claude`, then /login) or the Codex CLI instead of "add a Gemini API key".
  - **Daily recap provider list:** now Qwen (local), Claude, ChatGPT and None. It dropped "Dayframe backend", which always failed and could have posted cards to an old upstream server, and the un-configurable Gemini. Stored values for those move to local.
  - **Provider routing:** a saved Gemini or Dayflow Pro primary/backup moves to the local model on load, because Settings can no longer edit them. Onboarding and legacy migration default to local, not Gemini.
  - **Failure toasts:** no more "Gemini is free" / "Dayflow Pro required" advice. They now point to Ollama / Qwen.
  - **App menu:** removed "Check for Updates…" and the dead "Flow: Simulate Distraction / Nudge Style" items. The release notes say "Welcome to Dayframe" instead of "Flow is in beta". The GitHub-star check (which ran `gh` and called GitHub's API) is off.
  - **Onboarding:** the referral survey step is skipped; it only fed removed analytics.
  - **Naming:** the window title, bundle name, macOS permission prompts (screen, automation, microphone, all languages), the sample "Installed Dayframe!" card, idle cards, error messages and the export filename now say Dayframe.
  - **Tests:** the test targets point at Dayframe.app and sign locally (they couldn't run before). Four tests were updated to Dayframe behavior: local default, and the renamed Codex message.
- **Files:** `App/Dayflow/App/DayflowApp.swift`, `App/Dayflow/Core/AI/{DailyRecapModels,LLMProviderRouting,LegacyLLMProviderMigration,LLMService,LLMTypes,TimelineFailureClassifier}.swift`, `App/Dayflow/Core/Analysis/IdleBatchClassifier.swift`, `App/Dayflow/Core/Recording/StorageManager+TimelineCards.swift`, `App/Dayflow/Info.plist`, `App/Dayflow/InfoPlist.xcstrings`, `App/Dayflow/Views/Onboarding/OnboardingFlow.swift`, `App/Dayflow/Views/UI/{ChatView,ChatView+Content,WhatsNewView}.swift`, `App/Dayflow/Views/UI/Settings/OtherSettingsViewModel.swift`, `App/Dayflow.xcodeproj/project.pbxproj`, `App/DayflowTests/{LLMProviderRoutingTests,AgentClientRegistrationTests}.swift`
- **Why:** The user asked to "audit the entire app to make sure each function is working" and chose "fix them all".
- **Checked:**
  - Build passed.
  - `xcodebuild test -only-testing:DayflowTests`: 189 passed, 1 failed. The failure, `OpenAICompatibleProviderTests.testCardRetryRetainsFullContextAndReturnsDetailedCards`, is in upstream code nobody changed, so it already failed upstream.
  - App screenshot: Timeline recording, "Generating your next card", gap filled.
  - The failed 11:53 batch was re-run with Retry under the new timeout.
- **Known, left as is:**
  - The existing "Installed Dayflow!" card in today's data keeps its old title (data, not code).
  - Deep links and routes to the removed Flow/Agents/Support tabs are unreachable, so they were left.
  - Daily never unlocks if Mac notifications are denied (upstream behavior).
- **Commit:** see `git log`

### 14:35: Recording fixed, and safeguards so it can't silently stop again
- **What:**
  - **Root cause.** Recording stopped at 13:34. The app had been signed three different ways in one day (by hash, then the "Dayframe Local" cert at 13:59, then ad-hoc with a fixed requirement at 14:04). macOS kept the Screen Recording grant for an old signature. `tccd` logged "Failed to match existing code requirement" and denied every capture. Flipping the switch in Settings doesn't refresh that.
  - **One-time fix (done by the user):** `tccutil reset ScreenCapture local.dayframe.app`, then Allow.
  - **Stable signing, locked in.** `build-and-install.sh` signs ad-hoc with the fixed requirement `identifier "local.dayframe.app"`. This replaces the 13:59 certificate approach: no keychain prompt, and the same identity every build. The build fails if the requirement ever changes, and a DO-NOT-CHANGE note explains why.
  - **AI timeouts.** Ollama calls had a 60 s limit. Qwen 3.5 4B takes up to about 60 s per screenshot, so about 30 calls timed out and then retried, piling on more load. On-device endpoints now get 300 s; remote ones keep 60 s (`OllamaProvider+Networking.swift`).
  - **One batch at a time.** A new `BatchRunGate` in `AnalysisManager` stops batches from overlapping on the local model (batches 3 and 4 had run together).
  - **Stuck batches recovered.** At launch, batches left `processing`/`pending` by a quit are reset and re-run (`interruptedBatchIds`). Batches 3 and 4 (12:25–12:55) had been stuck since a rebuild; they completed and the gap is filled.
  - **No lost minutes on rebuild or quit.** The app catches SIGTERM and quits properly. `applicationWillTerminate` closes the open video segment, so a rebuild kept 0 of 0 frames lost instead of dropping up to 10 minutes. The build script quits Dayframe gracefully (TERM, then wait, then KILL).
  - **Never fails quietly:**
    - The in-app "Screen recording access needed" notice now shows for any onboarded user. Before, it was hidden unless a saved `isRecording` preference existed, so it never showed. It gained "Restart Dayframe" and "Already on but still blocked? Reset permission" (runs `tccutil reset` on Dayframe's own entry and asks again).
    - A Mac notification "Dayframe isn't recording" appears when blocked (at most hourly) and opens the fix.
    - The watchdog restarts capture if recording is "on" but no frame was saved for 3+ minutes while you're at the Mac.
    - Resuming from a pause now goes through the permission-aware path.
    - Onboarding's "Quit & Reopen" actually reopens.
  - **Keep-alive agent.** `Keepalive/local.dayframe.keepalive.plist` is installed by the build script to `~/Library/LaunchAgents`. Every 2 min it reopens Dayframe, and Ollama, if either isn't running. It skips while installing.
  - **Pause choices.** "∞" was replaced by "3 Hrs" in the menu bar and the Timeline pill. Recording is always on, so ∞ was undone by the watchdog within 30 s.
  - The Week view's Paused/Resume pill is now clickable. "Check for Updates" was removed from the menu bar (Sparkle is gone; it did nothing).
  - The support-chat page and Flow overlay no longer start at launch (`DayframeFlags`). The chat page had been reloading a hidden web view every 60 s.
  - **Briefing doctor.** The `recorder` check now uses the newest screen frame (15 min), not the newest card (2 h). That old check reported OK through this outage. Deployed to `~/Briefing/app`.
- **Files:** `build-and-install.sh`, `Keepalive/local.dayframe.keepalive.plist` (new), `App/Dayflow/App/{AppDelegate,PauseManager,RecordingControl,RecordingWatchdog}.swift`, `App/Dayflow/Core/AI/OllamaProvider+Networking.swift`, `App/Dayflow/Core/Analysis/AnalysisManager.swift`, `App/Dayflow/Core/Recording/{ScreenRecorder,StorageManager+Reprocessing,StorageManager+Screenshots,StorageManaging}.swift`, `App/Dayflow/Core/Notifications/NotificationService.swift`, `App/Dayflow/System/ScreenRecordingPermissionNotice.swift`, `App/Dayflow/Utilities/Dayframe.swift`, `App/Dayflow/Views/UI/MainView/{Layout,WeekTimelineGridView}.swift`, `App/Dayflow/Views/UI/PausePillView.swift`, `App/Dayflow/Menu/StatusMenuView.swift`, `App/Dayflow/Views/Onboarding/ScreenRecordingPermissionView.swift`, `Briefing/briefing.py`
- **Why:** The user said recording wasn't working "like Dayflow" and wants it to never happen again.
- **Checked:**
  - After the reset, frames arrive every 10 s.
  - **Rebuilt and reinstalled:** the new process kept recording with no prompt, and `tccd` logged 0 "Failed to match" lines.
  - The segment open during the rebuild was saved (0 frames marked deleted).
  - Batches 3, 4 and 7 completed; Qwen calls now take 5–10 s each with no timeouts. The timeline went from 5 to 9 cards.
  - Keep-alive test: quit Dayframe, triggered the agent, and Dayframe was back in 1 s (logged in `/tmp/dayframe-keepalive.log`).
  - `briefing.py doctor` shows the recorder OK on a fresh frame; Briefing pytest is 85/86 (the same old failure).
- **Commit:** see `git log`

### 13:59: Dayframe now signed with the "Dayframe Local" certificate
- **What:**
  - The user created a self-signed "Dayframe Local" code-signing certificate in Keychain Access.
  - `build-and-install.sh` now signs by the certificate's SHA-1. Before, parsing the name picked up "(CSSMERR_TP_NOT_TRUSTED)" and signing failed.
  - The build was run from the user's Terminal so the keychain approval prompt could appear.
- **Files:** `build-and-install.sh`
- **Why:** With a stable signature, macOS keeps the Screen Recording permission across rebuilds, so Resume and recording keep working.
- **Checked:**
  - `codesign -dr -` now shows `identifier "local.dayframe.app" and certificate leaf = H"a88ad041…"` instead of a cdhash.
  - Dayframe relaunched.
  - The user still has to allow Screen Recording once for this signature.
- **Commit:** see `git log`

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
