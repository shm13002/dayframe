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

## 2026-10-13 (Tue)

### 22:19: Briefing's pop-ups now come out of the notch
- **What:** The "Where you left off" dialog, the check-in and session-goal text boxes, and the nudge/debrief notifications are gone. The owner chose the "quiet peek" style:
  - the notch pill grows one line under the notch (accent dot, the message, a chevron)
  - after 30 s, or 8 s for a nudge, it tucks away and Jarvis's eyes turn the palette accent until it's read
  - hover peeks again; a click opens a card in the pill's own style
  - the briefing card shows one paragraph, 3 numbered next steps, and a single footnote ("3 memories to confirm in Briefing"), with Open Briefing / Done
  - the check-in card has a one-line field (Return saves). The panel takes the keyboard without activating Dayframe
  - a nudge is a peek only
  - a newer briefing replaces an unread older one; questions queue; notices wait for the startup show to end
  - **AI-down briefing rewritten:** it no longer shows "(Local AI unavailable: Ollama error…)" with every open loop. It now says "The local AI was busy, so this comes from your open loops" and lists the 3 freshest loops (7 days or newer) plus "N more open loops in Briefing". The raw error goes to the log only.
  - **Hand-off:**
    - `briefing.py notch()` writes `~/Briefing/notices/<id>.json` and runs `open -g dayframe://notice?id=<id>`
    - Dayframe validates the id, reads and deletes the file, and writes `<id>.ack`; for a question it writes `<id>.answer`
    - with no ack in 3 s, Briefing deletes the notice and shows its old dialog, so nothing is lost when Dayframe is closed
    - message text never goes in the URL
  - Not changed (owner didn't pick it): the "Resume <project>?" dialog.
  - `BriefingSections` now separates "Question for you" and the trailing notes from the next steps, which also fixes the native Briefing screen listing them as steps.
- **Files:**
  - new: `App/Dayflow/Island/BriefingNotice.swift`, `App/DayflowTests/BriefingNoticeTests.swift`, `Briefing/tests/test_notch.py`
  - changed: `App/Dayflow/Island/NotchPillView.swift`, `NotchPillPanel.swift`, `IslandController.swift`, `App/Dayflow/App/AppDeepLinkRouter.swift`, `App/Dayflow/Views/UI/Briefing/BriefingService.swift`
  - changed: `Briefing/briefing.py`, `Briefing/tests/test_briefing.py`, `Briefing/tests/test_hardening.py`
  - docs: `START-HERE.md`, `AGENTS.md`, `logs.sh` (new log category `notice`)
- **Why:** The owner hates the gray system dialogs. They pop up out of nowhere, are walls of text, and don't look like Dayframe. They asked for messages from the notch that are smarter, sharper and good-looking.
- **Checked:**
  - `DAYFRAME_LOW_DISK_OK=1 ./check.sh --app`: 259 app tests (8 new; 1 skipped, 0 failures), 100 Briefing tests (5 new), 24 web tests.
  - The new tests cover:
    - hand-off: ack/answer/skip, path-traversal ids rejected, expiry
    - peek text, and question/notes kept apart from next steps
    - AI-down text has no raw error
    - fallback dialog when there's no ack
    - the URL carries only the id
  - Rendered each state to PNG with ImageRenderer and reviewed it: briefing peek, briefing card, AI-busy card, check-in card, nudge peek, unread eyes.
  - Live, after install: `briefing.show()` returned in 0.3 s; Dayframe logged "showing brief notice" (category `notice`); no dialog; `~/Briefing/notices/` left empty.
  - Recording continued (frame at 22:27:55), 0 ScreenCapture tccd mismatches.
  - Not tested live: typing a check-in answer (`ask` waits for the owner). Covered by unit tests both sides.
  - Disk is down to about 1.3 GB free after the builds.
- **Commit:** this entry's title is the commit subject.

### 21:40: Full-repo v2 audit, installer/doctor/test/preset fixes, and documentation sync
- **What:** Applied an outside audit (Argon, on the Dayframe-for-Gemini snapshot of 05b9dfb). Claude re-checked every finding against this repo before taking it. Records are in `docs/audits/2026-10-13T2232Z/`.
  - `Briefing/install.sh` no longer crashes on the deleted `Companion.swift`, which it used to copy under `set -e`. `PORT` is now set unconditionally. Without the file it removes the old companion agent and binary, and drops the stale `companion` entry from `~/Briefing/status.json`, so `doctor` stops reporting it LATE.
  - `Briefing/install.sh` no longer installs the original Dayflow cask (ADR 0007). It checks for `Dayframe.app` and warns if `Dayflow.app` is present. `uninstall.sh` text updated to match.
  - `build-and-install.sh`:
    - the disk check is now in MB, like `check.sh`, and accepts `DAYFRAME_LOW_DISK_OK=1` with 1000 MB or more free
    - it syncs `Briefing/dist` to `~/Briefing/app/dist`
    - it creates `~/Library/LaunchAgents` before copying the keep-alive
    - signing is unchanged
  - The local-model upgrade sheet, banner and "recommended" checks now use Qwen3.5 4B (`.qwen35Model4B`) instead of the old Qwen3-VL 4B.
  - `dashboard.html` Settings: added `llm_backend` (a select with ollama, claude_cli, codex_cli, grok_cli, openai) and `cli_model`, and the empty state now says Dayframe.
  - Two Briefing tests made platform-independent (they behave the same on the Mac).
  - Docs:
    - `logs.sh` and `AGENTS.md` list all 7 log categories
    - START-HERE no longer mentions Companion.swift or WelcomeEventGateTests
    - AGENTS.md says Briefing deploys with `install.sh`, which is safe now that the Companion is gone
    - Briefing README and the SwiftBar title updated
  - Not taken from the audit: its `.githooks/pre-commit`. Ours already existed and works; the audit's archive had just left it out.
  - Found while applying it: the `install.sh --check` port test grepped for `python`, but `lsof` prints `Python`. Briefing's own running dashboard was reported as "port in use by another app", so the preflight failed. It's case-insensitive now (`grep -qi`).
  - START-HERE §5: added `v1.1`. Saved as tag `v1.1` plus a backup in `~/Documents/Projects/Dayframe Versions/v1.1 (2026-10-13)/`.
- **Files:**
  - `Briefing/install.sh`, `Briefing/uninstall.sh`, `build-and-install.sh`, `logs.sh`
  - `AGENTS.md`, `START-HERE.md`, `Briefing/README.md`
  - `Briefing/dashboard.html`, `Briefing/swiftbar-briefing.5m.sh`
  - `Briefing/tests/test_briefing.py`, `Briefing/tests/test_improve.py`
  - `App/Dayflow/Views/UI/SettingsView.swift`, `App/Dayflow/Views/UI/Settings/SettingsProvidersTabView.swift`, `App/Dayflow/Core/AI/LocalModelPreset.swift`, `App/Dayflow/Views/UI/Settings/ProvidersSettingsViewModel.swift`
  - new: `docs/audits/2026-10-13T2232Z/` (AUDIT_CONTEXT_LOG, RECOMMENDATIONS, FINAL_SUMMARY, CLAUDE_INSTRUCTIONS)
- **Why:** After the 16:30 Companion removal, `install.sh` crashed and `doctor` would report LATE indefinitely. The installer could also reinstall the conflicting Dayflow app. The user asked for the audit to be applied and saved as the latest version.
- **Checked:**
  - Before applying, every audit diff was read against this repo:
    - `.qwen35Model4B` exists, and `preset` is in scope in the banner
    - every backend value is valid in `briefing.py`
    - `/api/companion` and `/api/anticipate` exist
    - the signing block is untouched
  - `./check.sh`: clean, 24 web + 95 Briefing tests. `DAYFRAME_LOW_DISK_OK=1 ./check.sh --app`: 251 tests, 1 skipped, 0 failures.
  - `./build-and-install.sh` at 21:45: build OK, stable signing, keep-alive OK. A new chunk started at 21:45:44 and frames kept arriving (21:46:34). `pgrep -x Dayflow` is empty.
  - The only tccd "Failed to match" line was 21:44 (Documents folder, during the Debug test-host run), not ScreenCapture.
  - `Briefing/install.sh --check`: all OK. One WARN: the original Dayflow.app is still installed (owner's call). `./install.sh` OK, auto-committed `~/Briefing/app` a11ffee.
  - `briefing.py doctor`: `companion` is now NEVER (was going LATE), the dashboard answers 200, and no companion LaunchAgent remains.
  - Still erroring and not part of this change: `wake` and `distill`, "Ollama error: timed out".
- **Commit:** this entry's title is the commit subject.

### 16:30: Companion orb removed (owner request)
- **What:** Deleted the Briefing companion orb (the cursor-trailing bubble with suggested questions). Stopped and removed its launch agent. The rest of Briefing (briefing, dashboard, distill, nightly, etc.) is untouched.
- **Files:** Deleted `Briefing/Companion.swift`, `Briefing/companion-mock.html`; outside the repo: `~/Briefing/app/BriefingCompanion`, `~/Briefing/app/Companion.swift`, `~/Briefing/app/companion-Info.plist`, `~/Briefing/companion.log`, `~/Library/LaunchAgents/com.dayflowbriefing.companion.plist`.
- **Why:** Owner no longer wants the orb on screen.
- **Checked:** Process gone, launch agent no longer listed. Left in place: `/api/answer` and companion code in `briefing.py`/`dashboard.html`, plus the companion steps in `install.sh` and README (rerunning install.sh now just prints a compile WARN for the companion).

### 14:51: START-HERE brought up to date, one to-do list, version v1.0 saved
- **What:**
  - **START-HERE.md** now covers everything up to today:
    - Grok: sign-in, provider, briefing writer, MCP.
    - Start of day's Focus and the Today's apps row.
    - The ring icon and where it's drawn, the `Web/` folder, and the Chat pills.
    - Section 4 corrected: Claude, ChatGPT and Grok are back as plan-based options. The island, Start of day and the safeguards are listed.
    - Known issues: all tests pass, and the inherited failures were fixed in c874439.
  - **Section 6 is the one to-do list:** what only the user can do, what's left for an AI session, and what's done.
  - **New "Saved versions" table (section 5):** each version gets a git tag, a backup in `~/Documents/Projects/Dayframe Versions/<version>/` (app zip + source zip) and a GitHub push.
  - This commit is tagged `v1.0`. The app's own version number stays Dayflow's 2.6.0 (`MARKETING_VERSION`), left unchanged.
- **Files:** `START-HERE.md`
- **Why:** The user asked to "save this as the latest copy of Dayframe and organize everything", and chose a version tag, a backup copy, a GitHub push, and tidying the project.
- **Checked:** Every claim in the new text was checked against the code and CHANGELOG (test counts from the 14:15 run, the c874439 fixes, file names). No code changed.
- **Commit:** this entry's title is the commit subject.

### 14:17: Installed 338a31b: today's Grok, icon, Focus, Today's apps and review fixes are in the app
- **What:** `./build-and-install.sh` at 14:16. It ships everything since the 11:41 install: Grok as a provider and an MCP client, the ring app icon and palette Dock icon, Start of day Focus, the Today's apps row, and the review fixes.
- **Files:** none (install only)
- **Why:** None of today's afternoon work was in the running app yet.
- **Checked:**
  - 3.5 GB free before the build. Build, stable signing and keep-alive OK. The new binary is running (14:16:11).
  - Recording: a new chunk started 2 s after launch and kept growing. `./logs.sh 10m` shows no errors or watchdog restarts.
  - The bundled `AppIcon.icns` (converted to PNG) is the eclipse ring, no longer Dayflow's flower.
  - Not yet seen by Claude: the live Dock tile (macOS may need `killall Dock` to drop the cached icon), the Briefing error banner and Today's apps row inside the app, and Grok in Settings (it needs `grok login`).
- **Commit:** this entry's title is the commit subject.

### 14:15: Review of the island, Briefing and settings code: errors are shown and logged, not dropped
- **What:**
  - **Briefing actions say why they failed.** Writing a briefing, to-dos, feedback, Ask, resume and the writer picker used to drop errors (`try?`), so a click could seem to do nothing. They now go through one `perform(...)` that logs (category `briefing`) and sets `lastError`. The native Briefing screen shows it as a banner with Dismiss.
    - New `BriefingServiceError` reads the service's own `{"error": …}` text (capped at 200 characters). A raw response body (e.g. HTML) is never shown; it reads "the Briefing service didn't answer".
    - A successful action clears the banner. The "couldn't read the briefing data" notice clears on the next good refresh.
  - **One Briefing address:** `BriefingPanelView` had its own copy of the port lookup. It now uses `BriefingService.baseURL`.
  - **Logged instead of silent:** `print` → `os.Logger` in `RecordingWatchdog` (category `recording`), `IslandShowPanel`, `IslandSound` (`island`). A show that can't start, and a failed read of the app's AI usage (`usage`), are now logged.
  - **Colors:** the pill's accent default comes from `DayframePalette.original`. Its fixed neutrals (it always sits on the black notch) are named once in `PillInk` instead of repeated hex strings.
  - **Kept on purpose:** `try?` on `Task.sleep` (cancellation) and in Briefing's lenient JSON decoding. The force unwraps of fixed localhost URLs and of Apple's standard 44.1 kHz mono audio format can't fail. Dayflow's own files (e.g. `StorageSettingsViewModel`'s `print`) are left alone so upstream diffs stay small (ADR 0001).
- **Files:** `App/Dayflow/Views/UI/Briefing/{BriefingService,BriefingView}.swift`, `App/Dayflow/Views/UI/BriefingPanelView.swift`, `App/Dayflow/Views/UI/Settings/AIUsageSection.swift`, `App/Dayflow/Island/{IslandShowPanel,IslandSound,NotchPillView}.swift`, `App/Dayflow/App/RecordingWatchdog.swift`, `App/DayflowTests/NotchIslandTests.swift`
- **Why:** Ticket clean-code/04: the code-smell review of the island, native Briefing, settings and Chat on Qwen (swallowed errors, duplicated values, unlogged decisions). Started in the earlier session and finished here.
- **Checked:**
  - New test `testBriefingFailureSaysWhy`: the server's message, no doubled period, HTML and a timeout both read as "didn't answer", the 200-character cap.
  - `./check.sh --app` (3.5 GB free): all clean, **251 tests, 0 failures** (1 skipped: the icon writer). Web 24 tests, Briefing 95 tests.
  - Not yet: seeing the banner in the installed app (next install).
- **Commit:** this entry's title is the commit subject.

### 14:03: "Today's apps" row on Briefing
- **What:**
  - Briefing shows the day apps from Settings › Start of day as a row under the header: click an icon to bring that app forward (opening it if needed), or press **Set up my day** to run Start of day now. It's on both the React page and the native fallback screen.
  - **Swift → page:** `BriefingPageContext.dayApps` carries each app's bundle ID, name and a 64 px PNG icon as a data URL. `DayAppIcon` makes each icon once and caches it. briefing.py's CSP already allows `img-src data:`.
  - **Page → Swift:** new messages `openApp` and `setUpDay`. `StartOfDay.bringForward(bundleID:)` opens **only apps on the user's list** and logs a refusal for anything else, so the page can't launch arbitrary apps.
  - **Web:** new pure `src/briefing/day-apps.ts` (`parseDayApps` keeps only a bundle-ID-shaped ID, a name and a PNG data URL), wired through `lib/bridge.ts` and `main.tsx` into a `TodaysApps` component. It reuses the page's PillButton, motion tokens and theme colors.
  - `Briefing/dist` rebuilt and deployed to `~/Briefing/app/dist`.
- **Files:** `Web/src/briefing/{day-apps.ts,day-apps.test.ts,briefing-page.tsx,main.tsx}`, `Web/src/lib/bridge.ts`, `App/Dayflow/Views/UI/Briefing/{BriefingReactView,BriefingView}.swift`, `App/Dayflow/Welcome/StartOfDay.swift`, `App/DayflowTests/NotchIslandTests.swift`
- **Why:** The third idea the user asked to build now (ticket start-of-day-extras/03).
- **Checked:**
  - Web: 3 new parser tests (24 total), typecheck clean.
  - App: message parsing for `openApp`/`setUpDay`, `dayApps` in the context JSON, refusal of a non-day-app bundle ID, and the cached PNG data URL. `DAYFRAME_LOW_DISK_OK=1 ./check.sh --app`: all clean, 250 tests.
  - In the browser pane against the real Briefing server (`/app/?embed=dayframe`), with stand-in icons pushed through `window.dayframe.setContext`: the row renders with "Open Notes / Open Calendar / Open Cursor / Set up my day". A malformed entry (icon URL not a data URL) was dropped. It looks right in dark Original and light Lagoon, and the console is clean.
  - Not yet: clicking it inside the app (needs the install), and the user has no day apps set yet (Settings › Start of day › Add app…).
- **Commit:** this entry's title is the commit subject.

### 13:57: Start of day can turn on a Focus (through a Shortcut)
- **What:**
  - macOS has no public API to set a Focus, so Dayframe uses the supported path. The user makes a Shortcut once with the **Set Focus** action (suggested name "Work Focus"), and Start of day runs it with `/usr/bin/shortcuts run` right after the day's apps open.
  - New `FocusShortcut` (lists and runs shortcuts; the list parsing is pure and tested).
  - New setting key `dayframeStartOfDayFocusShortcut` ("" means none).
  - The run is logged (category `startofday`), and the Settings line ends "Work Focus is on." or "Work Focus didn't run."
  - **Settings › Start of day › Focus** (new section): a picker of the user's shortcuts that rechecks every 5 s while visible, so a shortcut just made in Shortcuts appears; "Open Shortcuts"; and "Run now" to try it.
- **Files:** `App/Dayflow/Welcome/{FocusShortcut,StartOfDay,StartOfDaySettingsView}.swift`, `App/DayflowTests/StartOfDayTests.swift`
- **Why:** One of the three ideas the user asked to build now (ticket start-of-day-extras/02).
- **Checked:**
  - New tests: the summary with a Focus that ran or failed, and parsing of `shortcuts list` output. `DAYFRAME_LOW_DISK_OK=1 ./check.sh --app`: all clean, 248 tests.
  - `shortcuts list` on this Mac returns nothing: **the user has no shortcuts yet.** Making "Work Focus" in Shortcuts (Set Focus → Work → On) is the user's step, then picking it in Settings › Start of day › Focus.
- **Commit:** this entry's title is the commit subject.

### 13:51: New app icon: the welcome's ring, and the Dock follows the palette
- **What:**
  - **New `AppIconArt`** (SwiftUI Canvas): the welcome's final mark. That is the night-sky tile, the eclipse ring with its corona and soft-to-sharp rim, and the three locks at rest. It uses the proportions and colors of `scene.ts` (ring radius 44 of the tile's 74, `LOCK_ANGLES`, `welcomeColors`) on Apple's icon grid (824 of 1024, continuous corners). The glow is clipped to the tile.
  - **Bundled AppIcon** (Finder, Launchpad, the Dock when Dayframe isn't running): the Original palette at every size, 16 to 1024 px. Generated by `AppIconTests.testWriteBundledAppIcon`, which only writes when asked: `TEST_RUNNER_DAYFRAME_WRITE_APP_ICON=1 xcodebuild test … -only-testing:DayflowTests/AppIconTests/testWriteBundledAppIcon`. It replaces Dayflow's orange flower.
  - **`AppIconManager`** (started by `AppDelegate`): while Dayframe runs, the Dock icon is redrawn in the active palette, and it changes when the palette does.
  - The wallpaper-dump comment now gives the `TEST_RUNNER_` prefix; xcodebuild only passes on variables with that prefix.
- **Files:** `App/Dayflow/Welcome/AppIconArt.swift`, `App/Dayflow/App/AppDelegate.swift`, `App/Dayflow/Assets.xcassets/AppIcon.appiconset/*`, `App/DayflowTests/{AppIconTests,StartOfDayTests}.swift`
- **Why:** One of the three ideas the user asked to build now (ticket start-of-day-extras/01).
- **Checked:**
  - New test: every palette at 16 and 1024 px has the right size, transparent corners and a solid middle.
  - Inspected the 512, 256 and 16 px PNGs by eye. The first render had glow spilling outside the tile; it's clipped now. At 16 px the ring still reads (the locks drop out).
  - `DAYFRAME_LOW_DISK_OK=1 ./check.sh --app`: all clean, 246 tests (1 skipped: the icon writer).
  - Not yet: seeing it in the Dock. That comes with the next install; macOS may need `killall Dock` to drop its cached icon.
- **Commit:** this entry's title is the commit subject.

### 13:47: Grok can read Dayframe (MCP); Grok Bot can't yet, and why
- **What:**
  - **Settings › MCP / CLI lists "Grok CLI".** Connect registers Dayframe's MCP server through Grok's own command, so Dayframe never edits `~/.grok/config.toml` itself: `grok mcp add dayflow --scope user -- <bundled dayflow> mcp` (`remove` to disconnect).
    - Status comes from `grok mcp list --json`, run from the home folder so a project's own Grok config can't change the answer. A different path or a switched-off entry counts as stale.
    - `repairStaleRegistrations()` repoints Grok at launch if the app moved.
  - New `GrokMCPRegistration` with an injectable command runner, like `CodexMCPRegistration`.
  - **Grok Bot (`/Applications/Grok Bot.app`), checked and not possible today:**
    - It keeps no local MCP configuration. Its Application Support has only Electron state, and its bundle has no "install MCP server" link.
    - Its only MCP link is `grokbot://mcp/oauth/callback`, which is for signing in to remote servers.
    - Dayframe's server is local (stdio), so there is nothing Dayframe can register. Ticket grok/04 records this.
  - `check.sh --app` gains a low-disk mode. `DAYFRAME_LOW_DISK_OK=1` allows an incremental build with 1 GB+ free, while a watchdog stops it below 600 MB. It formalizes the run the user approved at 13:42.
- **Files:** `App/Dayflow/Core/AgentAccess/{GrokMCPRegistration,AgentClientRegistration}.swift`, `App/Dayflow/Views/UI/Settings/SettingsAgentAccessTabView.swift`, `App/DayflowTests/GrokMCPRegistrationTests.swift`, `check.sh`, `.scratch/grok/issues/04-grok-reads-dayframe.md`
- **Why:** The user asked to connect "grok bot and grok"; this is the "Grok reads Dayframe" half. Ticket grok/04.
- **Checked:**
  - Ran `grok mcp add/list/remove` once in a throwaway folder at project scope to see the exact config and JSON. The user's `~/.grok/config.toml` was untouched.
  - 5 new tests: status from Grok's list (not installed / available / connected / stale), the exact add arguments with the user's other servers untouched, the error message, remove only when present, repair after a move.
  - `DAYFRAME_LOW_DISK_OK=1 ./check.sh --app`: all clean, **244 tests, 0 failures**.
  - Not yet: connecting for real. It needs the new build installed; then Settings › MCP / CLI › Grok CLI › Connect.
- **Commit:** this entry's title is the commit subject.

### 13:42: Grok as a full app provider (timeline, Chat, daily recap), with shared CLI code instead of copies
- **What:**
  - **Grok is a fourth AI provider** next to Qwen, Claude and ChatGPT. It runs xAI's Grok CLI signed in with the user's own plan (`grok login`, no API key, ADR 0003). It's chosen in onboarding, Settings › Providers (routing, connection test, "Grok CLI detected") and the Chat pill, and it can write the daily recap.
    - **Timeline:** Grok's headless mode takes no images, so Grok transcribes from the frames' **on-screen text** (Apple Vision OCR plus app hints, from the same input builder Claude uses), then writes cards. Card turns run with every tool removed.
    - **Chat:** streams and resumes its session (`-r`). It gets only the shell, to query the timeline with sqlite3, like Claude and Codex Chat.
    - Models: `grok-4.5`, low effort for transcripts and cards, medium for Chat, text and recap.
  - **New pure pieces, unit-tested:**
    - `GrokCLICommand` builds the arguments. The prompt goes in a private 0600 file (`--prompt-file`), deleted after the run, never on the command line.
    - `GrokCLIOutput` reads `json` and `streaming-json`, including the real "Not signed in" line.
    - `GrokCLI.executable()` prefers `~/.grok/bin/grok`, which isn't on every shell's PATH.
  - **Less copied code (deep modules):**
    - Codex's card loop moved to `AgentCLISupport+StreamingCards.swift` as `StreamingCardWriter`, used by Codex and Grok. It only adds the `disableTools` option for Grok; Codex behaves the same.
    - `CodexProvider+Text` and `ClaudeProvider+Text` were identical except for model names. They are now one `CLITextProvider` (`AgentCLISupport+Text.swift`) where each provider names its models. Grok's text and Chat are a few lines.
    - Chat's identical `buildCodexPrompt` / `buildClaudePrompt` became one `buildCLIPrompt`. Grok uses the shared CLI system prompt.
    - Claude's private segments-to-observations mapping is now shared, so Grok didn't need a third copy.
    - Onboarding's CLI detection stores one status per tool (`cliStatus[tool]`), and the view loops over all CLIs instead of naming each.
  - **Bug fixed along the way:** the app logged every CLI call as provider `chat_cli`, so Settings › AI usage counted Claude's usage as ChatGPT. Calls are now logged as `codex_cli`, `claude_cli` or `grok_cli`. Rows from before this stay as they were.
  - `ChatCLITool.signInCommand` and `.shellCommand` replace the `codex ? "codex auth" : "claude login"` ternaries in the "CLI not found" messages.
  - An expired Grok sign-in is classified as "login expired" with the fix `grok login`.
  - `GrokLogo` asset made from the installed Grok Bot app's icon.
- **Files:**
  - New: `App/Dayflow/Core/AI/{GrokCLI,GrokProvider,GrokProvider+Transcription}.swift`, `App/DayflowTests/GrokCLITests.swift`, `App/Dayflow/Assets.xcassets/GrokLogo.imageset`
  - Moved: `CodexProvider+ActivityCards.swift` → `AgentCLISupport+StreamingCards.swift`, `CodexProvider+Text.swift` → `AgentCLISupport+Text.swift` (with `ClaudeProvider+Text.swift` merged in)
  - Changed: `ChatCLIRunner`, `ChatCLIProcessRunner`, `AgentCLISupport{,+Parsing,+Transcription}`, `ClaudeProvider+Transcription`, `LLMTypes`, `LLMService`, `ChatService`, `DailyRecap{Models,Generator}`, `TimelineFailureClassifier`, `StorageManager+TimelineCards`, onboarding (`ChatCLITestView`, `ChatCLIDetectionViews`, `ProviderSetupState`, `LLMProviderSetupView`, `OnboardingPrototypeChooseProviderStep`), Chat (`ChatView{,+State,+Actions,+Content}`, `ChatHistoryPanel`), Settings (`ProvidersSettingsViewModel{,+PromptOverrides}`, `SettingsProvidersTabView`)
- **Why:** The user asked to connect Grok "just like Claude". Tickets grok/01 and grok/02.
- **Checked:**
  - **239 app tests, 0 failures** (12 new in `GrokCLITests`: arguments, prompt file privacy and permissions, executable lookup, envelope and stream parsing, the runner's Grok output, Chat/recap/provider mapping, missing session, per-CLI usage names, text-only card turns).
  - The build compiles with every provider `switch` handling Grok. Swift style clean (418 files).
  - **Disk:** with only 1.3 GB free, the user chose to unload Qwen (`keep_alive: 0`) for the test run. Dayframe reloads it for its next batch. The tests ran with a watchdog ready to stop the build below 600 MB; free space stayed at 1.3 GB.
  - **Not yet verified live:** the Grok CLI isn't signed in (its 7-day sign-in expired), so no real Grok card or Chat turn has run. **For the user:** `~/.grok/bin/grok login`, then Settings › Providers › Grok › Test. Images for Grok: ticket grok/05.
- **Commit:** this entry's title is the commit subject.

### 11:42: Installed 5c2695b; the welcome measured 59–60 fps in the app
- **What:** Installed the audit fixes and the `dayframe://` scheme (commit `5c2695b`). Then played both previews through `dayframe://welcome-preview` and read the frame rates the page reports.
- **Files:** none (install and measurement only)
- **Why:** In-app smoothness was the first "not yet tested" item from the Start of day work. There had been no frame-rate reading from the app.
- **Checked:**
  - `./logs.sh 2m welcome` shows `dailyWake show finished at 59 fps` and `firstLaunch show finished at 60 fps`, each `on 1 display(s)`.
  - Confirmed first, through `NSWorkspace`, that macOS opens `dayframe://` with `/Applications/Dayframe.app`. `pgrep -lx Dayflow` was empty afterwards.
  - After the install: newest frame 7 s old, 0 tccd "Failed to match" lines, and the new log line `login: skip: the welcome is off` (correct: the welcome is off until the user turns it on).
  - Still the user's checks: a real logout/login, a 10+ minute lock, an external display, the Accessibility layout (ticket start-of-day-extras/04).
- **Commit:** this entry's title is the commit subject.

### 11:41: Dayframe gets its own link scheme, dayframe:// (a dayflow:// link opened the original Dayflow app)
- **What:**
  - **Incident (caused by this session):** testing the new preview link with `open "dayflow://welcome-preview"` launched the Homebrew **Dayflow.app** (`/Applications/Dayflow.app`, also v2.6.0) instead of Dayframe, because macOS binds the `dayflow:` scheme to Dayflow. The two apps must never run together (ADR 0007).
    - Dayflow ran for about a minute and was quit with `pkill -TERM -x Dayflow`.
    - Effect: about 4 extra frames at 11:37 (10 instead of 6). No new cards. Same app version and schema (`user_version` 0). A backup from 11:01 exists.
    - Dayframe kept recording (latest frame 8 s old when checked).
  - **Fix:** `Info.plist` also claims `dayframe`, and `AppDeepLinkRouter` accepts `dayframe://` and `dayflow://`. Dayframe's own links use `dayframe://`. The preview is `dayframe://welcome-preview?variant=dailyWake|firstLaunch`.
  - The in-app `dayflow://category-editor` link is handled inside the app by a SwiftUI `openURL` handler, never by macOS, so it is unaffected.
- **Files:** `App/Dayflow/Info.plist`, `App/Dayflow/App/AppDeepLinkRouter.swift`
- **Why:** So a Dayframe link can never start the original app on the shared data folder. Saved as a memory lesson too.
- **Checked:**
  - `./check.sh --app`: all clean, 227 tests.
  - `pgrep -lx Dayflow` is empty. Frames are back to 6 per minute.
  - **Suggestion for the user:** uninstall the original app with `brew uninstall --cask dayflow`, so nothing can start it.
- **Commit:** this entry's title is the commit subject.

### 11:36: Grok in the native Briefing menu and in Settings › AI usage
- **What:**
  - The native Briefing screen's "Briefings are written by" menu lists Grok (`grok_cli`).
  - Settings › Providers › AI usage counts Briefing's `grok_cli` calls as "Grok" (gray bar). There is no plan-usage link: xAI's usage page for CLI plans isn't known, so none is guessed.
- **Files:** `App/Dayflow/Views/UI/Briefing/BriefingView.swift`, `App/Dayflow/Views/UI/Settings/AIUsageSection.swift`
- **Why:** These finish 11:11 (Briefing writes with Grok), which had to wait for an app build.
- **Checked:** Built and tested in the 11:35 `./check.sh --app` run (227 pass). Swift style clean.
- **Commit:** this entry's title is the commit subject.

### 11:35: Start of day: audit fixes (decisions logged, external-display fix, one source for show timings)
- **What:** From auditing commit `0c28ded` (ticket clean-code/03):
  - **Every welcome decision is logged** with its reason (category `welcome`), so after a real logout or a long lock `./logs.sh 1h welcome` says why it did or didn't play. Examples: `login: play: new login session, 31 s old`, `back: skip: away 5.0 min, needs 10.0 min`, `away (screen locked)`.
    - The gates now return a `WelcomeDecision` (play plus a reason) instead of a bare Bool.
    - `WelcomeLoginGate.shouldPlay` is renamed `decide`.
  - **Bug, external displays:** on "started" the show faded the *first* screen's cover, assuming it was the main display. With a second monitor that could be the wrong one, which would show the desktop on that display mid-show. The panel now keeps direct references to the main display's panel and cover.
  - **One source for the show's timings:** `WelcomeShowPanel` had its own copies of 5.45 / 2.0 / 0.8 s. The page now sends its length with "started" (`duration`), and the other displays' fade is timed from that. The timings live only in `Web/src/welcome/scene.ts`.
  - **StartOfDay:**
    - Each app is reported and logged as opened, already open, or couldn't open, with the error (failures used to be swallowed by `try?`). Placement is logged per app, and so is "Accessibility isn't allowed".
    - The Settings line now reads e.g. "Ran at 9:01 AM: 1 opened, 2 already open, 2 placed." (new `StartOfDayReport`; it used to count already-open apps as "opened").
    - Dayframe's own window placement now moves the **main** window (new `MainWindowController.window`), not the first visible window, which could be Settings.
    - The AX window lookup checks the CF type instead of force-casting.
  - `WallpaperManager` is started by `AppDelegate`, no longer as a side effect of `WelcomeController.start()`.
  - Settings › Window style: the Accessibility poll is a `.task` loop that runs only while the section is visible. It replaces a `Timer.publish` created inside the view struct.
  - **New deep link** `dayflow://welcome-preview?variant=dailyWake|firstLaunch` plays a preview, so the in-app frame rate can be measured from Terminal without clicking (`open …`, then `./logs.sh 5m welcome`).
  - Tests: `WelcomeEventGateTests.swift` renamed `StartOfDayTests.swift` (it also covers slots, wallpaper and assets). The wallpaper test writes its 12 PNGs only when `DAYFRAME_DUMP_WALLPAPERS=1`. New tests check the skip reasons and the run summary.
  - `check.sh --app` deletes the previous test result bundle first (about 100 MB each on this small disk).
  - The 23:34 entry is corrected: its Files list named a file that commit didn't touch, and its Commit line is now `0c28ded`.
- **Files:** `App/Dayflow/Welcome/{WelcomeController,WelcomeShowPanel,StartOfDay,StartOfDaySettingsView}.swift`, `App/Dayflow/Welcome/Resources/welcome.html` (rebuilt), `Web/src/welcome/main.ts`, `App/Dayflow/App/{AppDelegate,DayflowApp,AppDeepLinkRouter}.swift`, `App/DayflowTests/StartOfDayTests.swift` (renamed), `check.sh`, `CHANGELOG.md`
- **Why:** The user asked for an audit of the Aether Pulse / Start of day work, with clean code and everything logged.
- **Checked:**
  - `./check.sh --app`: **all clean**. 227 app tests, 0 failures; Briefing 95; web 21; Swift style clean. This is the first fully green run.
  - Not installed yet. The real login, the 10-minute lock and the external display are still the user's checks (ticket start-of-day-extras/04); the new log lines are there to read afterwards.
- **Commit:** this entry's title is the commit subject.

### 11:11: Briefing can write with Grok (grok_cli)
- **What:**
  - `briefing.py`: a third CLI backend, `grok_cli`, next to `claude_cli` and `codex_cli`. It runs xAI's Grok CLI signed in with the user's own plan (no API key) and falls back to Qwen on any error, like the others.
    - The three repeated `claude … else codex` choices are replaced by one table, `CLI_BACKENDS` (binary, display name, sign-in hint). Before this, adding a third CLI to `is_cli` alone would have run `codex`.
    - `~/.grok/bin` is added to the CLI search folders.
    - Grok can't read stdin, so the prompt goes in a private 0600 file in `~/Briefing/.cli-sandbox` (`--prompt-file`), deleted after the run, never on the command line. The system prompt goes through `--system-prompt-override`.
    - Grok writes text only: one turn, no web search, subagents, memory or plan, and every tool denied (`GROK_DENIED_TOOLS`).
    - Reads Grok's `json` output (`text`, `usage`: uncached plus cached input, output) and its error line. "Not signed in" gets the hint "run `grok login`".
  - Writer picker on the React Briefing page: Grok added. `Briefing/dist` rebuilt.
- **Files:** `Briefing/briefing.py`, `Briefing/tests/test_cli_backend.py`, `Web/src/briefing/briefing-page.tsx`, `.scratch/grok/issues/03-briefing-backend.md`
- **Why:** The user asked to connect Grok "just like Claude". Ticket grok/03.
- **Checked:**
  - 4 new tests (text and usage; the prompt goes through a removed file and never the arguments; text-only flags; "Not signed in" plus Qwen fallback): red first, then green.
  - Briefing 95 pass. Web typecheck, Prettier and tests pass.
  - The real CLI was run once with a two-word prompt. It is **not signed in** (its sign-in lasts 7 days). The error JSON it printed is the one the tests use. **For the user:** run `~/.grok/bin/grok login`.
  - Not yet: the native Briefing menu and Settings › AI usage entries for Grok (two small Swift edits) wait for the next app build. The disk has only about 2 GB free, below the build's 3 GB guard.
  - Correction to 11:08: its commit's hook ran **91** Briefing tests on the staged snapshot. The 95 counted these Grok tests, which were still unstaged then.
- **Commit:** this entry's title is the commit subject.

### 11:08: Tests stop acting on the real Mac, and the known test failures are fixed
- **What:**
  - **Briefing's tests acted on the real Mac** (the user saw this on every test run):
    - `test_cli_smoke` runs Briefing's real commands on fake data. `brief` showed the real "Where you left off" dialog and blocked until OK was clicked. `resume` (with `BRIEFING_TEST_RESUME=yes`) activated Cursor, Figma and Zoom and opened the fixture link `github.com/me/site/pull/12` in Chrome, which is where the row of GitHub "Page not found" tabs came from.
    - Other tests posted real notifications ("Gentle nudge", "Your weekly report is ready").
    - Nothing stopped tests from recording the microphone (`record_whisper`), sending an iMessage (`push`) or adding Things to-dos either.
    - Cause: every function that acts on the Mac called `osascript`, `open`, `say` or `ffmpeg` directly, guarded only by a patchwork of test variables.
  - **Fix:** one entry point, `run_on_mac()` in `briefing.py`. All 14 call sites go through it: dialogs, notifications, speech, the microphone, Messages, Things, and opening apps, files and links. With `BRIEFING_NO_DESKTOP=1` it records the command in `DESKTOP_CALLS` instead of running it. Approved automations also don't execute under that switch.
  - **Tripwire:** `tests/mocks.py` (imported by every test file) sets `BRIEFING_NO_DESKTOP=1`, and makes `subprocess.Popen` raise if a test reaches `osascript`, `open`, `say`, `afplay`, `ffmpeg`, `screencapture` or `shortcuts` any other way. Its first run caught the two notification paths.
  - **Briefing gate bug:** the self-improvement gate ran a candidate's new test by dotted name (`tests.improve_cases.test_x`). A `tests` package in the user's Python site-packages (`~/Library/Python/3.9/lib/python/site-packages/tests`) shadowed Briefing's folder, so every new test failed to import. The "fails before the fix" check passed for the wrong reason, the "passes after" check never could, and no code improvement could ever be accepted. New `run_new_tests()` runs each file by path, and rejects a test that doesn't import ("new test doesn't run").
  - **Git variables leaking into tests:** while a commit runs, git exports `GIT_INDEX_FILE` and similar variables. Briefing's self-improvement tests (throwaway repos and worktrees) inherited them and failed only inside the hook.
    - `improve.py`: every git call and every test run it starts now uses `clean_env()`, which drops those variables, so the loop only ever touches the repo it names.
    - `check.sh`: runs test suites through `without_git_env`. Its own git calls still use the variables, since they read the staged files.
  - **`check.sh --staged`** now runs the web and Briefing tests on an exact copy of the staged files (`git checkout-index` into a temp folder, about 1.3 MB). What is committed is what was tested, even with other edits still unstaged.
  - `cli_chat` and `cli_bin` (they launch the AI CLIs) are added to the self-improvement loop's `PROTECTED_FUNCS`.
  - **App:** `testCardRetryRetainsFullContextAndReturnsDetailedCards` looked for a `Previous cards:` label that Dayflow's card prompt no longer uses (it wraps them in `<previous_cards>`). The test was stale; it now checks the tag.
- **Files:** `Briefing/briefing.py` (only the `run_on_mac` change; the Grok backend is the next entry), `Briefing/improve.py`, `Briefing/tests/{mocks,test_briefing,test_hardening,test_improve}.py`, `check.sh`, `App/DayflowTests/OpenAICompatibleProviderTests.swift`, `.scratch/clean-code/issues/{06,07}-*.md`
- **Why:** The user asked for the popups on every test run to stop, for the cause to be found, and for the code to be clean. Tickets clean-code/06 and 07.
- **Checked:**
  - Red first for each new test: `test_commands_never_touch_the_real_mac` (no `DESKTOP_CALLS`), `test_new_test_must_run_to_count_as_failing`, `test_git_only_touches_the_repo_it_names` ("not a git repository"), and the extended protection test. Before the fix the tripwire raised on the two notifications.
  - After: Briefing 95 pass in about 34 s with nothing on screen (the run that showed the dialog took 89 s, because it waited for the click).
  - The hook-only failure reproduced with a throwaway `GIT_INDEX_FILE` (3 improve tests failed) and passes after the fix.
  - Dayframe's own index and branches were checked and are intact.
  - App: `OpenAICompatibleProviderTests` (3) and `WelcomeEventGateTests` (14) pass.
- **Commit:** this entry's title is the commit subject.

### 00:11: Swift: Dayframe's own files formatted to zero swift-format warnings
- **What:**
  - `xcrun swift-format format -i` on all 35 Swift files Dayframe created (Welcome, Island, native Briefing, settings sections, chat on Qwen, the recording watchdog, tests). Only formatting, except two `forEach` loops rewritten as `for` loops.
  - In 12 Dayflow files, fixed by hand only the lines Dayframe had added: line breaks, indentation, and a trailing comma. Dayflow's own warnings in those files are left alone (ADR 0001).
  - Small edits that go beyond whitespace:
    - `LocalModelPreset.qwen35_4B` renamed `qwen35Model4B`. The stored raw value `"qwen35_4b"` is unchanged, so saved settings still load.
    - `ChatMetadataParser.extractTrailingBareSuggestions`: the multi-line `guard` split into a named `lastLineStart` plus a short `guard`, with the same logic.
    - `OllamaProvider`'s `reasoning_effort` keeps its JSON name, marked `// swift-format-ignore: AlwaysUseLowerCamelCase`, like Dayflow's own `max_tokens`.
  - **check.sh fixes:** newer swift-format prints a "reading stdin without `-` is deprecated" notice, which was being counted as a warning (it inflated the 23:54 count). It now passes `-` and counts only real rule warnings.
- **Files:** 35 files under `App/Dayflow` and `App/DayflowTests` (formatting), `check.sh`, `.scratch/clean-code/issues/02-format-dayframe-swift.md`
- **Why:** Ticket clean-code/02. Dayframe's code had drifted from the style Dayflow uses (81 warnings in the Start of day files alone).
- **Checked:**
  - `./check.sh`: Swift clean (415 files).
  - `./check.sh --app` built the app and ran 226 unit tests: all pass except the known upstream `testCardRetryRetainsFullContextAndReturnsDetailedCards`, which is fixed in the next entry.
  - Briefing: 93 tests pass.
  - Not installed yet: installing comes after the audit fixes.
- **Commit:** this entry's title is the commit subject.

### 00:04: Web: Prettier everywhere, palette parity test, island tests
- **What:**
  - Ran Prettier (print width 120) over all of `Web/src` and the Vite configs. Whitespace and line breaks only.
  - **New `src/theme/palettes.test.ts`:** reads `App/Dayflow/Utilities/DayframePalette.swift` and checks that every palette's stops and accents match `paletteStops()`, including Original's fallback. The colors are written in both Swift and TypeScript; now a change on one side fails the tests.
  - **New `src/island/island.test.ts`:** easing endpoints, path length and normals, the spring settling within a second, the tracked-time labels ("3h 19m"), and each show's beat sheet (sounds in order, everything before `doneAt`).
  - Rebuilt `island.html` and `welcome.html`: byte-identical, so nothing to commit.
- **Files:** `Web/src/**` (formatting), `Web/src/theme/palettes.test.ts`, `Web/src/island/island.test.ts`, `Web/vite*.ts`, `.scratch/clean-code/issues/05-web-format-and-parity.md`
- **Why:** Ticket clean-code/05. Values shared between Swift and the web were mirrored by hand with only a comment holding them together.
- **Checked:**
  - Vitest: 21 pass. Typecheck clean. `prettier --check src` clean.
  - Mutation check: changing Lagoon's accent in the Swift file to `1C9E95` made the parity test fail ("expected '1C9E94' to be '1C9E95'"). Restored.
  - **Disk:** only about 400 MB free, because swap grew to 13 GB under memory pressure (Ollama/Qwen 6.3 GB, about 5 GB of Chrome tabs, plus Codex, Cursor and Grok Bot). The Swift formatting from ticket clean-code/02 stays uncommitted until there is room to build and test it.
- **Commit:** this entry's title is the commit subject.

## 2026-10-12 (Mon)

### 23:54: Clean-code groundwork: Matt Pocock's skills, AGENTS.md, check.sh gate, tracked hooks
- **What:**
  - **Matt Pocock's skills** (`mattpocock-skills` from the official Claude plugin marketplace) installed for the user, and the repo set up the way its `setup-matt-pocock-skills` describes: tickets as local markdown in `.scratch/<feature>/issues/` with a `Status:` line, the default triage labels, single-context domain docs.
  - **`AGENTS.md`** (new): the rules any AI (Claude, Grok, Codex) follows here: read order, the iteration loop (ticket → red/green test → `./check.sh` → CHANGELOG → one commit), code standards, guardrails. `CLAUDE.md` just imports it.
  - **`CONTEXT.md`** (new): the glossary (card, batch, show, welcome, first launch, daily wake, slot, palette…).
  - **`docs/adr/0001–0007`** (new): the decisions that are hard to undo: forking Dayflow, stable signing, no API keys, Qwen's small context, web surfaces in WebKit, login-session detection, the shared data folder.
  - **`./check.sh`** (new), the gate:
    - Swift: no file may have more swift-format warnings than Dayflow's original (new Dayframe files: zero). The config `.swift-format` pins Apple's defaults, which Dayflow's own code already follows.
    - Web: typecheck, Prettier, Vitest.
    - Briefing: unittest.
    - The newest CHANGELOG entry must be dated today and have What/Files/Why/Checked.
    - `--staged` checks only what's staged; `--app` also builds and runs the app's unit tests.
  - **`.githooks/pre-commit`** runs `./check.sh --staged`. Git uses it through `core.hooksPath`, and it replaces the untracked `.git/hooks/pre-commit`, so the hook is now versioned.
  - **`./logs.sh`** (new): Dayframe's own log lines for the last N hours, optionally for one area.
  - **Web:** Prettier 3.9.10 (print width 120, closest to the existing style) and Vitest 4.1.11 as pinned dev dependencies. New scripts `test`, `format`, `format:check`, `check`. First tests: `src/welcome/scene.test.ts` checks the welcome's timeline against the Aether cue sheet.
  - **`.gitignore`:** stopped ignoring `CLAUDE.md` and `agents.md`, rules inherited from Dayflow that would have silently kept the agent docs out of git (macOS ignores case).
  - **Tickets** for the rest of this pass: `.scratch/clean-code/` (6), `.scratch/grok/` (4), `.scratch/start-of-day-extras/` (4, one for the user).
  - `START-HERE.md`: lists the new files and commands.
- **Files:** `AGENTS.md`, `CLAUDE.md`, `CONTEXT.md`, `docs/adr/*`, `docs/agents/*`, `.scratch/**`, `check.sh`, `logs.sh`, `.githooks/pre-commit`, `.swift-format`, `.gitignore`, `START-HERE.md`, `Web/{package.json,package-lock.json,.prettierrc.json,vitest.config.ts,tsconfig.json}`, `Web/src/welcome/scene.test.ts`
- **Why:** The user wants every iteration clean and logged, using Matt Pocock's techniques (deep modules, test first, small steps, a shared glossary, review against standards), so the app is easier to keep building.
- **Checked:**
  - Vitest: 7 pass. Typecheck clean.
  - `./check.sh` runs end to end and reports today's starting point honestly: 41 Swift files over their limit, 18 web files not Prettier-formatted, and the known Briefing failure `test_code_candidate_from_model_goes_through_gate` (88 run). The next tickets fix these.
  - This commit passes `./check.sh --staged` (no Swift staged).
  - First attempt caught a gate bug: the CHANGELOG check read the template inside the code block at the top of this file instead of the newest real entry, so an empty entry would have passed. It now reads the first `###` under the first dated `##` heading. The hook also refused the amend until this file was updated, as intended.
- **Commit:** this entry's title is the commit subject.

### 23:34: Start of day: on-brand Aether opening, Dayframe wallpaper, Dayframe as the hub
- **What:**
  - **Opening animation, rebuilt natively** from the Aether Pulse "System Awakening" cut, in the active palette (`Web/src/welcome/`, bundled as `App/Dayflow/Welcome/Resources/welcome.html`).
    - Same beats as the reference and its cue sheet: the spark falls (0.2–1.6 s), the orbit draws, the vortex spins up (1.8 s), ignition (2.6 s), the eclipse ring and three locks (3.42 / 3.55 / 3.68 s), then the logo tile and the **Dayframe** wordmark with "Your day, in frame" (3.8–4.3 s), and a dissolve to the desktop (5.0–5.4 s).
    - Two cues: **first launch** (5.4 s, after login) and **daily wake** (2 s, ring only, after an unlock).
    - All colors come from `paletteStops()` (new in `Web/src/theme/palettes.ts`, mirrored by `DayframePalette.stops`).
    - Canvas 2D with glow sprites; the bloom is a quarter-size copy blurred by a CSS filter on the compositor. No SVG filters (see 21:56).
    - Pure function of time, so `window.welcome.render(payload, t)` draws any frozen frame.
  - **Sound:** the four Aether masters (48 kHz WAV) converted to AAC with `afconvert`. Settings offers Off, Mac speakers (laptop mix, default) or Headphones (cinematic mix). Playback starts on the page's first frame.
  - **`WelcomeShowPanel`** (new): every display gets a cover in the palette's deep sky, shown immediately so nothing flashes behind the page while it loads. The page runs on the main display. Click or any key skips. The panels are registered with `IslandCaptureExclusion`, so the show never appears in recordings.
  - **`WelcomeController`** (rewritten from Codex's):
    - Login is detected per **login session** (`CGSSessionUniqueSessionUUID`, plus the Dock's age under 4 min). The keep-alive agent's launch at login now plays too, and a relaunch in the same session never does.
    - Unlock away-time uses the wall clock, so sleep counts. The threshold is a setting (default 10 min).
    - Enabling the welcome marks the current session as seen, so a rebuild doesn't play a "login" show mid-day.
  - **`WallpaperManager`** (new): a textless wallpaper (palette sky, low horizon glow, a faint ring, three dunes), rendered at each display's native pixels. It is applied to every display and re-rendered when the palette, the appearance or the displays change. It shows behind the lock screen. Your previous wallpaper is remembered and restored when it's turned off (a dynamic wallpaper can't be read back, so then Wallpaper settings opens).
  - **`StartOfDay`** (new), after the login welcome:
    - Dayframe opens on **Briefing** (new `.navigateToBriefing`).
    - Your day's apps open in the background.
    - Other apps are hidden (not quit).
    - Windows go to their slots (Layout style). Dayframe's own window needs no permission; other apps need Accessibility, which the user grants.
    - Stage Manager style skips the layout.
  - **Settings → Start of day** (new tab): Opening, Wallpaper (live preview), Your day (apps, slots, Run now), Window style.
- **Removed:** Codex's SwiftUI fire ring (`WelcomeView.swift`), `WelcomeSettingsSection.swift`, `welcome-fire.m4a` (audio from an unrelated video with no license) and its provenance note. `DayflowWindowBackground` is private again.
- **Files:** `App/Dayflow/Welcome/{WelcomeController,WelcomeShowPanel,WallpaperManager,StartOfDay,StartOfDaySettingsView}.swift`, `App/Dayflow/Welcome/Resources/*`, `App/Dayflow/Utilities/DayframePalette.swift`, `App/Dayflow/Views/UI/{SettingsView,MainView/MainView}.swift`, `App/Dayflow/App/AppDelegate.swift`, `App/Dayflow/Island/IslandController.swift`, `App/DayflowTests/WelcomeEventGateTests.swift` *(corrected 2026-10-13: this list named `SettingsOtherTabView.swift`, which the commit didn't touch, and missed AppDelegate and IslandController)*, `Web/src/welcome/*`, `Web/vite.welcome.config.ts`, `Web/{package.json,tsconfig.json}`, `Web/src/theme/palettes.ts`, `START-HERE.md`
- **Why:** The user wants opening the Mac to feel like one product: a branded background behind the password, the Aether animation right after it, then Dayframe as the hub with everything else organized. Everything is on brand and in the palette, and the lock screen must not say Dayframe.
- **Checked:**
  - Typecheck is clean. Frozen frames at 0.6, 1.2, 1.8, 2.62, 3.0, 3.6 and 4.5 s were compared with the reference cut: beats, sizes and positions match. Checked in Original, Lagoon, Lavender and Ember, and the daily wake in Ember.
  - `WelcomeEventGateTests`: 14 pass. They cover unlock gating, keep-alive login launch, same-session relaunch, late launch, slot frames, wallpaper rendering in 6 palettes × light/dark at 2560×1664, and the bundled assets. The wallpapers were inspected by eye.
  - Build and install pass; signing is unchanged. A recording frame arrived 4 s after the relaunch, and there were 0 tccd "Failed to match" lines since the install (the 2 earlier ones were the Debug test host, Documents folder).
  - **Not yet checked:**
    - In-app Preview and its fps log. The user declined computer control, so they run it themselves.
    - A real logout/login, a 10+ min lock, an external display, and the Accessibility layout.
  - The welcome stays **off** until turned on in Settings → Start of day.
- **Commit:** `0c28ded`

### 22:45: Dayframe Welcome fire ring (Codex; never committed, superseded by 23:34)
- **What:** Added an integrated, palette-aware fire-ring welcome, reference audio, preview-first settings, login/unlock event handling, skip controls and reduced-motion fade. Reuses the app background and suppresses the notch’s automatic unlock welcome when enabled.
- **Files:** `App/Dayflow/Welcome/`, app lifecycle/background, Other settings, island controller and `WelcomeEventGateTests.swift`.
- **Why:** Make signing in feel like opening one cohesive Dayframe workspace.
- **Checked:** Native build, four event-gate tests and a rendered design snapshot passed. Installed-app preview completed and returned to Dayframe. Real login/unlock, multi-display and system-mute checks remain manual. Automatic playback defaults off until previewed and enabled. Audio provenance recorded for the personal build.


### 21:56: Island goo on the GPU (14 → 58 fps)
- **What:**
  - **New `Web/src/island/liquid.ts`:**
    - The black and white liquid layers keep their Canvas 2D drawing, now into an offscreen canvas at 1 px per point.
    - WebGL then runs the same math the SVG filter used: Gaussian blur σ 7 (separable, paired bilinear taps) and alpha × 22 − 9. Only that last threshold pass runs at Retina size, so edges stay crisp.
    - An idle white layer costs nothing.
    - Falls back to the old `filter: url(#goo)` if WebGL is missing or a shader fails (it swaps in a fresh canvas). `?goo=svg` forces the fallback, for side-by-side comparison in the dev page.
  - **New `Web/src/island/canvas.ts`:** `CanvasRegion`, `setupCanvas`, `sizeCanvas` and `clear` moved here from `engine.ts`, so both the engine and the liquid layers use them.
  - **`engine.ts`:** uses `LiquidLayer` for goo and white. `drawWhite` returns whether it drew anything.
  - **`main.ts`:** Reduce Motion clears the liquid layers through `LiquidLayer.clear`.
  - **`island.css`:** the SVG filter applies only to `.svg-goo`.
- **Files:** `Web/src/island/{liquid.ts,canvas.ts,engine.ts,main.ts,island.css}`, `App/Dayflow/Island/Resources/island.html` (rebuilt)
- **Why:** WebKit runs SVG reference filters on the CPU at device resolution every frame, which held the startup show to 14 fps. Chrome uses the GPU for them, which is why the prototype looked smooth in a browser.
- **Checked:**
  - Typecheck is clean.
  - Dev page with a frozen clock and seeded randomness: the WebGL and `?goo=svg` frames at 0.3 s (drip), 0.58 s (burst and drips), 1.25 s (white splats), 1.6 s and 6.4 s (collapse) look the same. No console warnings.
  - In the app, Play now gives `startup show finished at 58 fps` (was 14). The show panel is up for ~7 s, then the pill returns.
  - Recording: new segment 3 s after install; 0 tccd "Failed to match".
- **Commit:** see `git log`

### 21:40: Installed the island fixes; show frame rate measured (14 fps)
- **What:**
  - Freed disk so the build could run. At the user's request, 38 stale Chrome `code_sign_clone` copies were deleted, keeping the one the running Chrome uses. Only about 3 GB came back (13 → 16 GB free): `du` said 86 GB, but the clones were APFS copy-on-write and shared blocks with Chrome.
  - Installed `af2b9f2`'s pending show fixes: the demo bar stays hidden in the app, and the canvases are sized to the island area.
  - The fps line never logged. `body["fps"] as? Double` dropped the number WebKit hands over, so it's now read as `NSNumber` and logged with `os.Logger` (subsystem `local.dayframe.app`, category `island`, public values).
- **Files:** `App/Dayflow/Island/IslandShowPanel.swift`
- **Why:** To finish the open items from 21:14, and so the show's frame rate can actually be read: `/usr/bin/log show --predicate 'subsystem == "local.dayframe.app" AND category == "island"'`. In zsh, plain `log` is a shell builtin, so always use `/usr/bin/log`.
- **Checked:**
  - Build, signing check and install all pass.
  - New recording segment within 3 s of relaunch; 0 tccd "Failed to match" since the install (checked with `/usr/bin/log`).
  - Play now: the show panel (1470×956, level 1000) is up for ~7 s, then the pill returns.
  - The log reads `startup show finished at 14 fps`. Low Power Mode is off and load is low.
  - Recorded frames: the pill isn't visible at the notch, and no dimmed show frames appear in the 21:26 segment.
- **Open:**
  - **The show runs at 14 fps.** Probable cause: `filter: url(#goo)` on two canvases. WebKit renders SVG-reference filters on the CPU at Retina resolution every frame, while Chrome uses the GPU, which is why the prototype was smooth in a browser. Shrinking the canvases doesn't help much, because the filter still runs at full device resolution. The likely fix is to draw the liquid layers in WebGL (the same blur + threshold, done on the GPU). Waiting on the user.
  - Still to test: the real unlock trigger (lock the Mac for 10+ min).
- **Commit:** see `git log`

### 21:14: React Briefing, liquid notch island ("Jarvis"), Web design system
- **What:**
  - **`Web/` (new):** Vite 8 + React 19 + TypeScript + Tailwind 4 + Motion 14 + shadcn/Magic UI (number-ticker, blur-fade).
    - `src/theme/palettes.ts` + `tokens.css` mirror `DayflowTheme.swift` / `DayframePalette.swift` (all 6 palettes, light/dark) with the app's Figtree + Instrument Serif fonts.
    - `src/components/dayframe/` is the Dayframe UI kit: GlassCard, PillButton, InkText (words settle in like ink), TodoRow (strike-through then fold), Menu, Stat, ActivityChip, skeleton sheen.
    - `kit.html` is a gallery of every token and component, made for `/design-sync`.
  - **Briefing tab in React** (`Web/src/briefing/`):
    - Same sections and layout as the native screen. One orchestrated entrance; the briefing text settles in word by word when a new briefing arrives; a skeleton shows while the model writes (button disabled, so no double runs); hours count up; check-offs fold away; errors are shown with Try again; Reduce Motion is respected.
    - Ask stays on `/api/ask`. `/api/answer` is the on-screen companion, which answers from screen text, not memory.
    - Swift side: `BriefingReactView` loads `http://127.0.0.1:8765/app/` and pushes palette, dark mode and category colors through `window.dayframe.setContext` (no reload). It falls back to the native `BriefingView` if `/app/` is missing or the page doesn't report ready within 4 s. "More" pages still open the old dashboard sheet. New `.navigateToTimeline` notification.
  - **briefing.py serves the build** at `/app/` from `dist/`:
    - Paths are unquoted, resolved and must stay inside `dist/`; `%2e%2e` traversal returns 400.
    - Explicit MIME map; charset only on text types; extension-less routes get the app shell.
    - `install.sh` copies `dist/` and git-ignores it in `~/Briefing/app`.
  - **Notch island** (`App/Dayflow/Island/` + `Web/src/island/`), built from the user's liquid-island-motion skill:
    - **Always-on pill** around the hardware notch: focus ring and percent on the left; Jarvis's eyes plus today's tracked time on the right. Eyes close while recording is paused, blink on their own and follow the pointer slightly. Hover shows a one-line summary; click opens a card with the next thing, Pause 30 min / Resume, Open Dayframe and Replay.
    - **Startup show** on unlock after 10+ min away (setting): dimmed glass, liquid drip and burst out of the notch, warp into a white blob that splats into eyes (blink, wink, ^^), then "Good evening, <name>" plus left off / next / today. Streams count up the focus ring and tracked time, the eyes dissolve into crescents, and it collapses into the pill. Any key or click skips.
    - **Moments:** new card (drip + blink), focus goal reached (short show, once a day), pause/resume (eyes close/open), end-of-day recap (category rings), each with a toggle.
    - **Sound:** `IslandSound` renders the skill's tone/tink/whoosh recipes with AVAudioEngine (no files; follows system volume; on/off and volume settings). The page only names cues, since WebKit won't start Web Audio without a click.
    - **Stats:** computed with `DaySummaryStats` exactly like Today's targets. The show is one bundled single-file `island.html`.
    - **Settings › Other › Notch island:** all toggles, the minutes-away threshold, your name, and Play now.
  - **Kept out of recordings:** `ScreenRecorder` skips frames while a show is on screen, and excludes the pill window (this app is excluded, all its other windows kept, so blocked apps still work). The window list is refreshed when island windows appear.
  - **Build:** `build-and-install.sh` runs `npm ci` + `npm run build` before xcodebuild. Signing is untouched. `node_modules` and `Briefing/dist` are git-ignored; `island.html` is committed.
- **Files:**
  - New: `Web/**`, `App/Dayflow/Island/*`, `App/Dayflow/Views/UI/Briefing/BriefingReactView.swift`, `App/Dayflow/Views/UI/Settings/NotchIslandSettingsSection.swift`, `App/Dayflow/Utilities/WeakScriptMessageHandler.swift`, `App/DayflowTests/NotchIslandTests.swift`
  - Changed: `AppDelegate.swift`, `DayflowApp.swift`, `MainView.swift`, `Layout+Panels.swift`, `BriefingView.swift` (BriefingMoreSheet internal), `SettingsOtherTabView.swift`, `ScreenRecorder.swift`, `RecordingWatchdog.swift` (lock check internal), `DailyRecapScheduler.swift` (recap hook), `DayframePalette.swift` (accentHex), `Briefing/briefing.py`, `Briefing/install.sh`, `Briefing/tests/test_hardening.py`, `build-and-install.sh`, `.gitignore`
- **Why:** The user asked for motion/UX improvements using React components, a Jarvis-style startup when they open the laptop, and their liquid-island skill (motion + sound) applied to Dayframe, with the design system ready for Claude Design.
- **Checked:**
  - Web typecheck clean.
  - Briefing tests: 88 run, only the known `test_code_candidate_from_model_goes_through_gate` fails; 2 new static-serving tests pass, including 6 encoded-traversal probes.
  - App tests: 212 run, only the known upstream `testCardRetryRetainsFullContextAndReturnsDetailedCards` fails; 10 new `NotchIslandTests` pass.
  - Live server: `/app/` 200, JS `text/javascript`, font `font/ttf`, `%2e%2e` 400, cross-origin 403.
  - In the app: the pill shows focus 74% (matches Today's targets 3.3/4.5 h) and 3h 19m tracked. Play now ran the startup show with real data ("Good evening, Shahzeb", left off, next).
  - Recording after each install: new frames within seconds, 0 tccd ScreenCapture "Failed to match". The 2 Documents-folder lines at 21:05 came from the unit-test host.
  - **Open:**
    - Demo-bar CSS fix and smaller canvases are built but not installed yet: the disk is at 2 GB free and the build needs 3 GB. 88 GB is in Chrome's `code_sign_clone` temp folder; the user needs to clear it.
    - The React Briefing cards' entrance only runs while the window is visible (WebKit pauses hidden pages).
    - Still to check: the real unlock trigger and the recorded-frame exclusion.
- **Commit:** see `git log`

### 17:50: Chat runs on Qwen; "Installed Dayflow!" card renamed
- **What:**
  - **Qwen in Chat.** A new chat provider, `local`, runs the same `fetchTimeline` / `fetchObservations` tool loop as Gemini, against Ollama's OpenAI-style endpoint (streaming, `tool_calls`, `reasoning_effort: "none"`).
    - It is the default. A **Qwen** pill sits first, before Codex and Claude. A one-time switch moved the stored `claude` (the old default, never actually chosen) to `local`; picking Claude later sticks.
  - **Fits Qwen's 4,096-token window:**
    - It keeps the last 6 messages and uses a short system prompt (`localSystemPrompt`).
    - Tool results are compact text: one line per card with its minutes, a total, and a 6,000-character cap.
    - `num_ctx` is never sent, because a different window size would reload the model and stall the timeline.
  - **Shared tools.** The tool code moved out of `GeminiDirectProvider` into `DashboardChatTools`; Gemini forwards to it, so its behavior is unchanged.
  - **Follow-up questions.** Qwen sometimes ends with a bare JSON list instead of a fenced `suggestions` block. The parser now turns that list into suggestion chips, so raw JSON never shows in the chat.
  - **Chat screen:**
    - Qwen readiness is checked through `/api/tags`, including that the model is listed.
    - Locked-screen and help text mention Qwen.
    - History shows "Qwen".
    - The privacy note no longer claims questions are logged (analytics is a no-op stub in Dayframe).
  - **The 10-hour unlock gate is unchanged**, as the user chose. Chat opens by itself once 10 hours have been analyzed.
  - **Sample card.** `StorageManager.migrate()` renames any "Installed Dayflow!" card to "Installed Dayframe!" (idempotent), which fixed card 8. Real cards that mention Dayflow work were left alone.
  - **Briefing's copies.** The same rename was applied to the Ollama sample card in `~/Briefing/memory`: journal lines 4 and 6, `daily/2026-10-12.md`, `projects/dayflow.md`, `data/project-dayflow.json`, and fact `628af85b`. The backup is in `memory/.backups/rename-sample-card-*`. The 11:41 card (the real Dayflow install with LM Studio) was kept.
- **Files:**
  - New: `App/Dayflow/Core/AI/DashboardChatTools.swift`, `App/Dayflow/Core/AI/OllamaProvider+DashboardChat.swift`, `App/DayflowTests/LocalDashboardChatTests.swift`
  - Changed AI code: `App/Dayflow/Core/AI/{LLMTypes,LLMService,ChatService,ChatPromptBuilder,ChatMetadataParser,OllamaProvider+Networking,GeminiDirectProvider+DashboardChat,GeminiDirectProvider+DashboardTools}.swift`
  - Changed app and UI: `App/Dayflow/App/AppDelegate.swift`, `App/Dayflow/Core/Recording/StorageManager.swift`, `App/Dayflow/Views/UI/{ChatView,ChatView+Actions,ChatView+Content,ChatView+State,ChatHistoryPanel}.swift`
  - Docs: `START-HERE.md`
- **Why:** The user asked to fix the two items left open at 14:37 ("Chat still can't use Qwen" and the old welcome card) and wants the app to work as intended. They chose Qwen as the default with Claude optional, and to keep the 10-hour gate.
- **Checked:**
  - Before building: a direct Ollama tool-call test returned `fetchTimeline {"date":"2026-10-12"}` in 2.6 s.
  - Unit tests: 202 run, 1 failure, the known upstream `OpenAICompatibleProviderTests.testCardRetryRetainsFullContextAndReturnsDetailedCards`. The 12 new tests pass.
  - The live test asked Qwen "What did I work on today?" against the real data. Qwen called `fetchTimeline`, answered in 7.7 s with today's actual work and plausible durations, and returned follow-up questions.
  - Installed twice. Recording kept going: a fresh frame within seconds each time, and 0 tccd "Failed to match" after install. The 3 at 17:47 came from the test-host build reading the Documents folder.
  - Screenshots:
    - The Timeline shows "Installed Dayframe!" at 12:57.
    - Chat shows the 10-hour gate (1h 45m / 10h) and the new privacy note.
  - The Mac was asleep about 14:50–17:41. That is the timeline gap, not a recording fault.
- **Commit:** `f3eb60b`

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
