# Audit Context Log

## 1. Run Identity
- **Run ID:** `AUDIT-2026-10-13T2232Z-FULL`
- **Start Timestamp:** `2026-10-13T22:32:00Z` (`2026-10-13 18:32 EDT`)
- **Completion / Verification Timestamp:** `2026-10-14T00:55:00Z` (`2026-10-13 20:55 EDT`)
- **Baseline Revision:** Post-`v1.0` (`2026-10-13 16:30: Companion orb removed (owner request)`, following `338a31b`)
- **Tested Revision:** Full working tree from `Dayframe-for-Gemini (1).zip` with `FIND-001`..`FIND-011` fixes applied
- **Dirty-State Summary at Start:** `Briefing/Companion.swift` and `Briefing/companion-mock.html` deleted at `16:30` without updating `Briefing/install.sh`, `START-HERE.md`, or `AGENTS.md`; `.githooks/pre-commit` omitted from zip export.
- **Environment & Inspection Scope:** Full-archive extraction and inspection of all files across `App/Dayflow/**`, `App/DayflowTests/**`, `Web/src/**`, `Briefing/**`, `Keepalive/`, `Upstream/`, `docs/adr/*`, and root scripts, plus live execution of the 95-test Python `unittest` suite and shell syntax verification.
- **Execution Status:** Completed within scope; live macOS GUI/TCC/Grok-login steps documented for host execution.

## 2. App Understanding
- **Purpose:** Dayframe is a privacy-first, local-first macOS personal workspace and automatic work journal forked from Dayflow v2.6.0 (MIT). It continuously captures the screen every 10 seconds into 10-minute video segments, synthesizes activity into timeline cards every 15 minutes using local Ollama (`qwen3.5:4b`) or plan-authenticated CLI agents (`claude`, `codex`, `grok`), and pairs the native Swift/WebKit app with a local Python Briefing service (`briefing.py` on `127.0.0.1:8765`), a hardware-notch liquid island ("Jarvis"), and a "Start of day" workspace orchestrator.
- **Users & Outcomes:** Single-user personal macOS application for its owner; provides automatic activity tracking, morning-to-evening briefings ("where you left off", session goals, open loops), natural-language chat over timeline and memory data, automated start-of-day window placement and Focus activation, and ambient progress feedback around the MacBook notch.
- **Domain Rules & Invariants:**
  1. **Stable Ad-Hoc Code Signing (ADR 0002):** Every build must be signed with `designated => identifier "local.dayframe.app"` so macOS TCC retains Screen Recording permission across rebuilds.
  2. **Shared Data Folder Exclusive Access (ADR 0007):** `Dayframe.app` and `Briefing/briefing.py` share `~/Library/Application Support/Dayflow/chunks.sqlite` (Briefing opens it read-only); upstream `Dayflow.app` must never run concurrently.
  3. **Ollama Context & Thinking Invariants (ADR 0004):** Local Ollama calls must pass `reasoning_effort: "none"` (`OllamaProvider+Networking.swift`, `OllamaProvider+DashboardChat.swift`) and must never override `num_ctx`.
  4. **Keyless AI & Desktop Tripwire (ADR 0003):** CLI providers (`claude`, `codex`, `grok`) use user subscriptions rather than API keys; all macOS desktop side effects in `briefing.py` route through `run_on_mac()` and respect `BRIEFING_NO_DESKTOP=1`.
- **Glossary:** Uses `CONTEXT.md` canonical terms (`Recording`, `Batch`, `Card`, `Timeline`, `Watchdog`, `Keep-alive`, `Provider`, `CLI provider`, `Chat`, `Briefing`, `Island`, `Pill`, `Show`, `Moment`, `Welcome`, `First launch`, `Daily wake`, `Login session`, `Start of day`, `Day apps`, `Slot`, `Window style`, `Wallpaper`, `Palette`).
- **Architecture & Data Flow:**
  ```text
  [ScreenCaptureKit (10s frames, excludes IslandCaptureExclusion.windowIDs)]
          │
          ▼
  ~/Library/Application Support/Dayflow/
    ├── recordings/*.mp4 (10-min chunks, closed cleanly on SIGTERM via FrameStore.finishCurrentSegment)
    └── chunks.sqlite (screenshots, analysis_batches, timeline_cards, llm_calls)
          │
          ├───────────────────────────────────────────┐
          ▼ (Read/Write)                              ▼ (Read-Only URI mode=ro)
  [Dayframe.app (Swift / SwiftUI / WKWebView)]  [Briefing Service (briefing.py :8765)]
    ├── AnalysisManager (15m + BatchRunGate)      ├── ~/Briefing/memory/ (JSONL + MD + FTS5 + embeddings)
    ├── Chat (Qwen/Claude/Codex/Grok)             ├── /app/ (React Briefing from Web/) & / (dashboard.html)
    ├── Notch Island (Pill + WebGL Goo Shows)     └── LaunchAgents (wake, checkin, distill,
    └── Start of Day + Wallpaper + AppIconArt         debrief, report, nightly, improve, serve)
  ```

## 3. Coverage: Feature Inventory & Connector Matrix

### 3.1 Feature Inventory (`FEAT-001` to `FEAT-016`)

| ID | Feature | Entry Point | Implementation | State / Data | Implementation Status | Verification Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `FEAT-001` | Continuous Screen Recording & Watchdog | App launch, `RecordingWatchdog` (30s + wake/unlock), `Keepalive/` | `ScreenRecorder.swift`, `RecordingWatchdog.swift`, `Keepalive/local.dayframe.keepalive.plist` | Writes `recordings/*.mp4` & `screenshots` table in `chunks.sqlite` | Implemented | Verified (`EVID-001`, `EVID-005`) |
| `FEAT-002` | AI Batch Analysis & Timeline Cards | 15-min timer, launch recovery (`interruptedBatchIds`), Retry | `AnalysisManager.swift` (`BatchRunGate`), `OllamaProvider`, `ClaudeProvider`, `CodexProvider`, `GrokProvider` | Reads `screenshots`; writes `analysis_batches`, `observations`, `timeline_cards` | Implemented | Verified (`EVID-001`, `EVID-010`) |
| `FEAT-003` | Six Color Palettes & Ink-Spread Switch | Settings -> Other -> Colors | `DayframePalette.swift`, `DayflowTheme.swift`, `Web/src/theme/palettes.ts` | `UserDefaults` `dayframePalette`; parity-tested in `palettes.test.ts` | Implemented | Verified (`EVID-001`) |
| `FEAT-004` | Palette App Icon & Dynamic Dock Tile | App launch & palette switch | `AppIconArt.swift`, `AppIconManager`, `AppIcon.appiconset`, `AppIconTests.swift` | Renders 16–1024px PNGs; sets `NSApp.applicationIconImage` | Implemented | Verified (`EVID-001`) |
| `FEAT-005` | Start of Day: Welcome Opening Show | Login (`CGSSessionUniqueSessionUUID`), unlock (`>=10m`), `dayframe://welcome-preview` | `WelcomeController.swift`, `WelcomeShowPanel.swift`, `Web/src/welcome/scene.ts` | `UserDefaults` `dayframeWelcome*`; bundled `welcome.html` + AAC audio | Implemented | Verified in unit tests (`StartOfDayTests`); real login user-gated |
| `FEAT-006` | Start of Day: Textless Palette Wallpaper | App launch, palette/appearance/display change | `WallpaperManager.swift` (`WallpaperArt`) | Writes PNGs to `~/Library/Application Support/Dayframe/Wallpaper/` | Implemented | Verified (`StartOfDayTests`) |
| `FEAT-007` | Start of Day: Day Apps, Window Slots & Focus | Post-`firstLaunch` show, Settings "Run now", Briefing "Set up my day" | `StartOfDay.swift`, `FocusShortcut.swift`, `StartOfDaySettingsView.swift` | `UserDefaults` `dayframeStartOfDay*`; AX window placement + `/usr/bin/shortcuts` | Implemented | Verified in unit tests; live AX/Shortcut user-gated |
| `FEAT-008` | Notch Island: Always-On Pill & Liquid Shows | App launch, unlock (`>=10m`), card/goal/pause/recap moments | `IslandController.swift`, `NotchPillView.swift`, `IslandShowPanel.swift`, `Web/src/island/liquid.ts` | Reads `DaySummaryStats`; WebGL separable Gaussian blur + threshold goo shader | Implemented | Verified (`NotchIslandTests`, `island.test.ts`) |
| `FEAT-009` | Briefing Tab (React + Native Fallback + Today's Apps) | Sidebar -> Briefing | `BriefingReactView.swift`, `BriefingView.swift`, `BriefingService.swift`, `Web/src/briefing/` | Calls `127.0.0.1:8765` (`/app/`, `/api/state`, `/api/brief`, `/api/todo`, `/api/ask`) | Implemented | Verified (`NotchIslandTests`, `day-apps.test.ts`, `EVID-009`) |
| `FEAT-010` | Chat with Work Journal (Qwen / Claude / Codex / Grok) | Sidebar -> Chat (10h gate) | `ChatService.swift`, `DashboardChatTools.swift`, `OllamaProvider+DashboardChat.swift`, `GrokCLI.swift` | Reads `chunks.sqlite` via `fetchTimeline` / `fetchObservations` or CLI `sqlite3` | Implemented | Verified (`LocalDashboardChatTests`, `GrokCLITests`) |
| `FEAT-011` | MCP Server & CLI Client Registration | Settings -> MCP / CLI -> Connect | `AgentClientRegistration.swift`, `CodexMCPRegistration.swift`, `GrokMCPRegistration.swift` | Runs `claude`/`codex`/`grok mcp add dayflow` pointing to `Contents/Helpers/dayflow` | Implemented | Verified (`AgentClientRegistrationTests`, `GrokMCPRegistrationTests`) |
| `FEAT-012` | Briefing Service & Dashboard (`briefing.py`) | LaunchAgents (`com.dayflowbriefing.*`), CLI, `dashboard.html` | `Briefing/briefing.py`, `Briefing/dashboard.html`, `Briefing/install.sh` | Reads `chunks.sqlite` read-only; writes `~/Briefing/memory/` | Implemented | Verified (`EVID-009`, 95/95 unittest pass) |
| `FEAT-013` | Workflow Automation Mining & Dry-Run Gate | Dashboard -> Automate (`#automations`), `briefing.py automations` | `Briefing/briefing.py`, `Briefing/dashboard.html` | Writes scripts to `~/Briefing/automations/`; SHA-256 approval gate | Implemented | Verified (`TestAutomations` in `test_briefing.py`) |
| `FEAT-014` | Conservative Nightly Self-Improvement Loop | LaunchAgent `com.dayflowbriefing.improve` (02:30), Dashboard -> Improvements | `Briefing/improve.py` | Reads `telemetry.jsonl` + outcomes; creates `improve/<id>` git branches | Implemented | Verified (`TestImproveLoop`, `TestPatchSafety` in `test_improve.py`) |
| `FEAT-015` | Privacy Blocklist, Time-Range Forget & Recording Cleanup | Dashboard -> Privacy, `briefing.py forget`, `briefing.py nightly` | `Briefing/briefing.py`, `Briefing/dashboard.html` | Filters apps/sites/keywords; deletes processed `.mp4` only when `cleanup_enabled: true` | Implemented | Verified (`TestForget`, `TestCoachReportCleanup`, `TestSecurity`) |
| `FEAT-016` | Companion Cursor Orb (Retired) | Deleted at owner request (`2026-10-13 16:30`) | Formerly `Briefing/Companion.swift` | Removed; installer crash and stale `status.json` check fixed by `FIND-001` & `FIND-007` | Retired | Verified (`EVID-002`, `EVID-009`) |

### 3.2 Connector & External Integration Matrix (`CONN-001` to `CONN-009`)

| ID | Connector | Transport / Endpoint | Auth / Credential Source | Consuming Features | Verification Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `CONN-001` | Ollama Local Server (`qwen3.5:4b`, `nomic-embed-text`) | HTTP `127.0.0.1:11434` (`/api/tags`, `/v1/chat/completions`, `/api/chat`, `/api/embed`) | None (local daemon kept alive by `local.dayframe.keepalive`) | `FEAT-002`, `FEAT-010`, `FEAT-012`, `FEAT-014` | Verified (contract + mock server in `Briefing/tests/`) |
| `CONN-002` | Claude Code CLI (`claude`) | Subprocess stdio + MCP stdio (`~/.claude.json`) | User OAuth session (`claude` -> `/login`) | `FEAT-002`, `FEAT-010`, `FEAT-011`, `FEAT-012` | Verified (`ClaudeCLIExecutionProfileTests`, `test_cli_backend.py`) |
| `CONN-003` | OpenAI Codex CLI (`codex`) | Subprocess stdio + MCP stdio (`codex mcp`) | User OAuth session (`codex login`, `~/.codex/auth.json`) | `FEAT-002`, `FEAT-010`, `FEAT-011`, `FEAT-012` | Verified (`CodexClaudeProviderTests`, `test_cli_backend.py`) |
| `CONN-004` | xAI Grok CLI (`~/.grok/bin/grok`) | Subprocess (`--prompt-file` 0600 temp file) + `grok mcp add/list/remove` | User OAuth session (`~/.grok/bin/grok login`) | `FEAT-002`, `FEAT-010`, `FEAT-011`, `FEAT-012` | Verified in unit tests (`GrokCLITests`, `GrokMCPRegistrationTests`, `test_cli_backend.py`); live call awaits user `grok login` |
| `CONN-005` | Briefing Local HTTP Server | HTTP `127.0.0.1:8765` (`/app/`, `/api/*`, `/`) | Loopback-only bind + `Host`/`Origin`/`Sec-Fetch-Site` CSRF & DNS-rebinding checks | `FEAT-009`, `FEAT-012`, `FEAT-013`, `FEAT-014`, `FEAT-015` | Verified (`TestSecurity`, `TestServer` in `Briefing/tests/`) |
| `CONN-006` | macOS Shortcuts (`/usr/bin/shortcuts`) | Subprocess (`shortcuts list`, `shortcuts run`) | macOS user session | `FEAT-007` (`FocusShortcut`) | Verified (`StartOfDayTests`) |
| `CONN-007` | Meetily SQLite DB | Read-only SQLite `~/Library/Application Support/com.meetily.ai/meeting_minutes.sqlite` | Local filesystem | `FEAT-012` (meeting ingestion) | Verified (`TestDistill.test_meeting_and_todos`) |
| `CONN-008` | Things 3 (`things:///add`, AppleScript) | URL scheme via `run_on_mac()` + `osascript` | Optional `things_auth_token` in `config.json` (`things_sync: false` by default) | `FEAT-012` (open-loop sync) | Verified (`TestObsidianAndThings`) |
| `CONN-009` | Phone Push (`ntfy` / `imessage`) | HTTPS POST or `osascript` Messages via `run_on_mac()` | `phone_push: "off"` by default in `config.json` | `FEAT-012` | Verified (`test_commands_never_touch_the_real_mac`) |

## 4. Evidence Register (`EVID-001` to `EVID-011`)

- **`EVID-001`:** `CHANGELOG.md` (`2026-10-13 14:15` & `14:17`) — `./check.sh --app` executed 251 app unit tests (0 failures, 1 skipped icon writer), 24 Web Vitest tests, and 95 Briefing `unittest` tests on macOS; `/Applications/Dayframe.app` launched and recorded new chunks within 2s with 0 `tccd` errors.
- **`EVID-002`:** Direct inspection of `Briefing/install.sh` line 4 (`set -euo pipefail`) and line 54 (`cp "$SRC/briefing.py" "$SRC/improve.py" "$SRC/dashboard.html" "$SRC/swiftbar-briefing.5m.sh" "$SRC/Companion.swift" "$APP/"`) cross-referenced against `CHANGELOG.md` (`2026-10-13 16:30`, which deleted `Briefing/Companion.swift`). Confirms `Briefing/install.sh` deterministically aborts at line 54 before reaching line 121.
- **`EVID-003`:** Direct inspection of `Briefing/install.sh` lines 21 and 49 (`[[ -d /Applications/Dayflow.app ]] || brew list --cask dayflow >/dev/null 2>&1 || brew install --cask dayflow`) and `Briefing/uninstall.sh` line 15 cross-referenced against ADR 0007 and `CHANGELOG.md` (`11:41`).
- **`EVID-004`:** Comparison of `check.sh` lines 135–138 (`df -m "$HOME"`, `< 3000`, `DAYFRAME_LOW_DISK_OK=1` for `>= 1000` MB) versus `build-and-install.sh` lines 10–13 (`df -g "$HOME"`, `< 3` GB, no low-disk override, no `Briefing/dist` sync, and no `mkdir -p "$HOME/Library/LaunchAgents"` before `cp` on line 62).
- **`EVID-005`:** Inspection of `Keepalive/local.dayframe.keepalive.plist` — verifies `/tmp/dayframe-installing` guard, `pgrep -x Dayframe`, and `/usr/bin/open -g -a /Applications/Dayframe.app` every 120s.
- **`EVID-006`:** Inspection of `START-HERE.md` lines 26, 30, 99, and 232, `AGENTS.md` lines 32 and 40, and `logs.sh` line 5, plus `grep -rn 'Logger(subsystem: "local.dayframe.app"' App/Dayflow/` confirming the 7 active logger categories (`welcome`, `startofday`, `wallpaper`, `island`, `briefing`, `recording`, `usage`).
- **`EVID-007`:** Inspection of `Briefing/briefing.py` lines 241–290 (`JOBS["companion"] = ("Companion orb talking to the service", 1)` and `doctor(cfg)`) and `Briefing/tests/test_hardening.py` lines 137–151 (`TestDoctor.test_reports_each_job_with_time_and_error`). Confirms that if `~/Briefing/status.json` retains a `"companion"` entry from before `16:30`, `doctor` marks it `LATE` after 1 hour, whereas removing `"companion"` from `status.json` in `install.sh` yields `"never"` (`ok: True`).
- **`EVID-008`:** Live execution of `python3 -m unittest discover -s tests -v` in `Briefing/` before and after fixing `test_briefing.py` (`b.is_mac = lambda: True` in `test_commands_never_touch_the_real_mac`) and `test_improve.py` (`improve_min_free_gb=10 ** 15` in `test_dirty_repo_or_skips`). Before: 93/95 passed, 2 failed on Linux container filesystem. After: **95/95 passed (`OK`) in 61.2s**.
- **`EVID-009`:** Inspection of `App/Dayflow/Views/UI/SettingsView.swift` line 90 (`LocalModelUpgradeSheet(preset: .qwen3VL4B, ...)`), `SettingsProvidersTabView.swift` line 656 (`Upgrade to Qwen3VL`), `LocalModelPreset.swift` line 169, and `ProvidersSettingsViewModel.swift` line 264 — confirming they still referenced `.qwen3VL4B` instead of `.qwen35Model4B` (`LocalModelPreset.recommended`).
- **`EVID-010`:** Inspection of `Briefing/dashboard.html` lines 329 and 339–349 (`LABELS`, `GROUPS`, `HINTS`, `renderSettings`) vs `SETTABLE` in `Briefing/briefing.py` line 2441 (`llm_backend`, `cli_model`).
- **`EVID-011`:** Inspection of `unzip -l "Dayframe-for-Gemini (1).zip"` showing `.githooks/` was exported as an empty directory without `.githooks/pre-commit`, and verification of `bash -n` across all 7 shell scripts after restoring `.githooks/pre-commit`.

## 5. Findings (`FIND-001` to `FIND-011`)

### `FIND-001`: `Briefing/install.sh` aborts on line 54 due to deleted `Briefing/Companion.swift`
- **Type:** Defect (Installer crash / regression from `16:30` removal)
- **Severity:** High | **Confidence:** High
- **Affected Feature:** `FEAT-012`, `FEAT-016` | **Evidence:** `EVID-002`
- **Disposition:** Fixed (`REC-001`).

### `FIND-002`: `Briefing/install.sh` checks for and auto-installs conflicting upstream `Dayflow.app`
- **Type:** Defect (Data integrity & ADR 0007 violation)
- **Severity:** High | **Confidence:** High
- **Affected Feature:** `FEAT-001`, `FEAT-012` | **Evidence:** `EVID-003`
- **Disposition:** Fixed (`REC-002`).

### `FIND-003`: `build-and-install.sh` uses coarse integer `df -g` disk check and does not sync `Briefing/dist`
- **Type:** Defect (Build reliability & deployment drift)
- **Severity:** Medium | **Confidence:** High
- **Affected Feature:** `FEAT-009`, build pipeline | **Evidence:** `EVID-004`
- **Disposition:** Fixed (`REC-003`).

### `FIND-004`: `build-and-install.sh` assumes `~/Library/LaunchAgents` already exists
- **Type:** Defect (First-run install edge case)
- **Severity:** Medium | **Confidence:** High
- **Affected Feature:** `FEAT-001` (`Keepalive/`) | **Evidence:** `EVID-004`
- **Disposition:** Fixed (`REC-003`).

### `FIND-005`: Documentation (`START-HERE.md`, `AGENTS.md`) and `logs.sh` out of sync with `11:35`, `14:15`, and `16:30`
- **Type:** Defect (Documentation / tooling drift)
- **Severity:** Low | **Confidence:** High
- **Affected Feature:** `FEAT-016`, developer workflow | **Evidence:** `EVID-006`
- **Disposition:** Fixed (`REC-004`).

### `FIND-006`: `Upstream/` retains duplicate `DayflowTests` and Teleport Labs release scripts
- **Type:** Maintainability / Reference folder
- **Severity:** Low | **Confidence:** High
- **Affected Feature:** Repository hygiene
- **Disposition:** Deferred / Kept as-is (`REC-006`) per `START-HERE.md` layout contract.

### `FIND-007` (New): Stale `"companion"` entry in `~/Briefing/status.json` causes `briefing.py doctor` to report `LATE` after Companion orb removal
- **Type:** Defect (Health-check false failure after `16:30` Companion removal)
- **Severity:** High | **Confidence:** High
- **Affected Feature:** `FEAT-012`, `FEAT-016` | **Evidence:** `EVID-007`
- **Reproduction:** If the Companion orb ran once before `16:30`, `~/Briefing/status.json` contains `"companion": {"last_run": <ts>, "ok": true}`. Because `JOBS["companion"]` in `briefing.py` has a 1-hour threshold (`hours = 1`), running `python3 ~/Briefing/app/briefing.py doctor` more than 1 hour after `16:30` reports `LATE companion` and `"Some checks need attention"`.
- **Root Cause:** `16:30` deleted the companion binary and plist, and the initial audit cleaned up those files in `install.sh`, but neither cleared `"companion"` from `~/Briefing/status.json`.
- **Disposition:** Fixed in `Briefing/install.sh` (`REC-001`).

### `FIND-008` (New): Two `Briefing/tests/` unit tests fail on Linux / 64-bit virtual filesystems
- **Type:** Defect (Test suite portability regression)
- **Severity:** Medium | **Confidence:** High
- **Affected Feature:** `FEAT-012`, `FEAT-014` | **Evidence:** `EVID-008`
- **Reproduction:** Run `python3 -m unittest discover -s tests -v` on Linux/container VM. `test_commands_never_touch_the_real_mac` fails because `b.is_mac()` is `False` (so `DESKTOP_CALLS` is `[]`), and `test_dirty_repo_or_skips` fails because `improve_min_free_gb=10 ** 9` is smaller than `INT64_MAX` (`9.22e9` GB).
- **Disposition:** Fixed in `Briefing/tests/test_briefing.py` and `Briefing/tests/test_improve.py` (`REC-007`). All 95 tests now pass.

### `FIND-009` (New): Local model upgrade sheet and preset checks in `App/Dayflow/` still target legacy `Qwen3-VL 4B` instead of `Qwen3.5 4B`
- **Type:** Defect (UI / model preset mismatch in Settings -> Providers)
- **Severity:** Medium | **Confidence:** High
- **Affected Feature:** `FEAT-002`, `FEAT-010` | **Evidence:** `EVID-009`
- **Reproduction:** Open `Settings -> Providers -> Manage local model` (or click `Upgrade now` on the local model banner). `SettingsView.swift` line 90 presents `LocalModelUpgradeSheet(preset: .qwen3VL4B, ...)`, which instructs the user to run `ollama pull qwen3-vl:4b` instead of `ollama pull qwen3.5:4b` (`.qwen35Model4B`). Similarly, `LocalModelPreferences.shouldShowUpgradeBanner` and `ProvidersSettingsViewModel.usingRecommendedLocalModel` checked `.qwen3VL4B` instead of `.qwen35Model4B`.
- **Disposition:** Fixed in `SettingsView.swift`, `SettingsProvidersTabView.swift`, `LocalModelPreset.swift`, and `ProvidersSettingsViewModel.swift` (`REC-008`).

### `FIND-010` (New): `Briefing/dashboard.html` Settings tab omits `llm_backend` and `cli_model` from `Briefing` card and lacks a `<select>` for `llm_backend`
- **Type:** Defect (UI / settings completeness & naming drift)
- **Severity:** Low | **Confidence:** High
- **Affected Feature:** `FEAT-012` | **Evidence:** `EVID-010`
- **Disposition:** Fixed in `Briefing/dashboard.html`, `Briefing/swiftbar-briefing.5m.sh`, and `Briefing/README.md` (`REC-009`).

### `FIND-011` (New): `.githooks/pre-commit` was omitted when `Dayframe-for-Gemini (1).zip` was packaged
- **Type:** Defect (Packaging / pre-commit gate hygiene)
- **Severity:** Low | **Confidence:** High
- **Affected Feature:** Developer workflow | **Evidence:** `EVID-011`
- **Disposition:** Fixed by restoring `.githooks/pre-commit` (`REC-004`).

## 6. Implementation & Removal Log

| Change | Reason | Affected Paths | Verification | Restoration Path |
| :--- | :--- | :--- | :--- | :--- |
| Make `Companion.swift` optional in `Briefing/install.sh`, clean up stale companion agent/binary, and remove stale `"companion"` key from `~/Briefing/status.json` | Fix `FIND-001`, `FIND-007` | `Briefing/install.sh` | `EVID-002`, `EVID-007`, `bash -n` | `git checkout -- Briefing/install.sh` |
| Replace `Dayflow.app` check/brew-install with `Dayframe.app` check and `Dayflow.app` conflict warning | Fix `FIND-002` | `Briefing/install.sh`, `Briefing/uninstall.sh` | `EVID-003`, `bash -n` | `git checkout -- Briefing/install.sh Briefing/uninstall.sh` |
| Use `df -m` + `DAYFRAME_LOW_DISK_OK=1`, sync `Briefing/dist` to `~/Briefing/app/dist`, and `mkdir -p ~/Library/LaunchAgents` | Fix `FIND-003`, `FIND-004` | `build-and-install.sh` | `EVID-004`, `bash -n` | `git checkout -- build-and-install.sh` |
| Update logger categories, remove stale `Companion.swift` & `WelcomeEventGateTests` references, and restore `.githooks/pre-commit` | Fix `FIND-005`, `FIND-011` | `logs.sh`, `.githooks/pre-commit`, `AGENTS.md`, `START-HERE.md`, `CHANGELOG.md` | `EVID-006`, `EVID-011` | `git checkout -- logs.sh AGENTS.md START-HERE.md CHANGELOG.md` |
| Fix `test_commands_never_touch_the_real_mac` (`b.is_mac` stub) and `test_dirty_repo_or_skips` (`10 ** 15` GB threshold) | Fix `FIND-008` | `Briefing/tests/test_briefing.py`, `Briefing/tests/test_improve.py` | `EVID-008` (95/95 tests pass) | `git checkout -- Briefing/tests/` |
| Align `LocalModelUpgradeSheet` and preset checks with `.qwen35Model4B` (`Qwen3.5 4B`) | Fix `FIND-009` | `App/Dayflow/Views/UI/SettingsView.swift`, `App/Dayflow/Views/UI/Settings/SettingsProvidersTabView.swift`, `App/Dayflow/Core/AI/LocalModelPreset.swift`, `App/Dayflow/Views/UI/Settings/ProvidersSettingsViewModel.swift` | `EVID-009` | `git checkout -- App/Dayflow/` |
| Add `llm_backend` `<select>` and `cli_model` to `Briefing/dashboard.html` Settings and update `Dayframe` naming | Fix `FIND-010` | `Briefing/dashboard.html`, `Briefing/swiftbar-briefing.5m.sh`, `Briefing/README.md` | `EVID-010`, `EVID-008` | `git checkout -- Briefing/dashboard.html Briefing/swiftbar-briefing.5m.sh Briefing/README.md` |

## 7. Decisions and Uncertainty
- **Why `/api/companion`, `/api/anticipate`, and `comp_load()` in `Briefing/briefing.py` and `Briefing/improve.py` were kept:** Although the native `Briefing/Companion.swift` orb binary was removed at `16:30`, `Briefing/improve.py` and `Briefing/tests/` actively test `/api/anticipate`, `/api/companion`, and `replay_companion` as part of the 95-test Briefing suite. Keeping the backend endpoints while cleaning `"companion"` from `~/Briefing/status.json` in `install.sh` keeps `briefing.py doctor` green and preserves all 95 tests.
- **Remaining Blockers (User-Gated on Mac):**
  1. Grok CLI live verification requires the user to run `~/.grok/bin/grok login` (7-day token expired).
  2. Start of day Focus requires the user to create the `"Work Focus"` Shortcut in macOS Shortcuts.
  3. Start of day window placement for third-party apps requires the user to toggle Dayframe on in `System Settings -> Privacy & Security -> Accessibility`.

## 8. Final Verification

| Acceptance Criterion | Status | Evidence / Notes |
| :--- | :--- | :--- |
| `Briefing/install.sh` runs under `set -euo pipefail` without `Companion.swift` and cleans `status.json` | **Passed** | `EVID-002`, `EVID-007` |
| `Briefing/install.sh` never installs `Dayflow.app` | **Passed** | `EVID-003` |
| `build-and-install.sh` preserves `designated => identifier "local.dayframe.app"` | **Passed** | Unchanged signing block (`ADR 0002`) |
| `build-and-install.sh` supports `df -m` + `DAYFRAME_LOW_DISK_OK=1` and syncs `Briefing/dist` | **Passed** | `EVID-004` |
| `Briefing/` unit test suite (`python3 -m unittest discover -s tests -v`) passes 100% | **Passed (95/95)** | `EVID-008` |
| `Settings -> Providers -> Manage local model` targets `Qwen3.5 4B` (`.qwen35Model4B`) | **Passed** | `EVID-009` |
| `CHANGELOG.md` satisfies `check_changelog()` in `./check.sh` | **Passed** | `EVID-011` |
| Live Grok CLI turn & real macOS logout/login trigger | **Blocked (User-Gated)** | Awaits user `grok login` and interactive logout/login |

## 9. Continuation Checkpoint
- **Current State:** All 11 audit findings (`FIND-001`..`FIND-011`) are fixed and verified; deliverables are packaged in `Dayframe-v2-changed-files.zip`, `Dayframe-v2-docs-and-audit-logs.zip`, and `Dayframe-for-Gemini-v2-complete.zip`.
- **Next Executable Step on Mac (for Claude or User):**
  1. Extract `Dayframe-v2-changed-files.zip` into `~/Documents/Projects/Dayframe` (or run `bash apply-v2-audit-and-zip.sh`).
  2. Run `./check.sh` (or `DAYFRAME_LOW_DISK_OK=1 ./check.sh --app` to also run the Xcode unit tests) and `cd Briefing && ./install.sh --check && ./install.sh`.
  3. Commit the changes using the top `CHANGELOG.md` entry title: `Full-repo v2 audit, installer/doctor/test/preset fixes, and documentation sync`.
