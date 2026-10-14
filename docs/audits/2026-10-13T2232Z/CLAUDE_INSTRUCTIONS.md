# Instructions for Claude Code — Apply Dayframe V2 Audit & Final Fixes

Give this file (along with `Dayframe-v2-changed-files.zip`) to Claude Code inside `~/Documents/Projects/Dayframe`.

---

## Prompt to Paste into Claude Code

```text
Read CLAUDE_INSTRUCTIONS.md and apply all changes from Dayframe-v2-changed-files.zip into ~/Documents/Projects/Dayframe.
1. Follow AGENTS.md and ADR 0001–0007 (never change how build-and-install.sh signs local.dayframe.app).
2. Extract Dayframe-v2-changed-files.zip (or apply each file listed in CLAUDE_INSTRUCTIONS.md) into the repository root.
3. Ensure today's date heading in CHANGELOG.md matches `date +%F` so `./check.sh` passes.
4. Run `./check.sh` (and `DAYFRAME_LOW_DISK_OK=1 ./check.sh --app` if >= 1000 MB free disk is available) to verify 0 Swift warnings, Web typecheck/Prettier/Vitest pass, and all 95 Briefing Python unit tests pass.
5. Run `cd Briefing && ./install.sh --check && ./install.sh` to update ~/Briefing/app and clean up any stale companion entry in ~/Briefing/status.json, then run `python3 ~/Briefing/app/briefing.py doctor`.
6. Stage all modified/new files and commit with the exact CHANGELOG entry title:
   "Full-repo v2 audit, installer/doctor/test/preset fixes, and documentation sync"
```

---

## What Changed and Why (11 Verified Findings: `FIND-001` to `FIND-011`)

### Confirmed from Initial `App Audit Dayframe` (`FIND-001` to `FIND-006`)
1. **`FIND-001` (`Briefing/install.sh`):** Line 54 previously ran `cp ... "$SRC/Companion.swift" "$APP/"` under `set -euo pipefail`, which immediately crashed `install.sh` after `Briefing/Companion.swift` was deleted in commit `16:30`. Also defined `PORT` inside the `if xcrun --find swiftc` block.
   - **Fix:** Removed `"$SRC/Companion.swift"` from line 54 `cp`, computed `PORT` unconditionally, wrapped the Companion build in `if [[ -f "$SRC/Companion.swift" ]] && xcrun --find swiftc >/dev/null 2>&1; then`, and cleaned up any stale `com.dayflowbriefing.companion` agent/binary in the `else` branch.
2. **`FIND-002` (`Briefing/install.sh`, `Briefing/uninstall.sh`):** `install.sh` checked for `/Applications/Dayflow.app` and ran `brew install --cask dayflow`, re-installing the conflicting upstream app that `ADR 0007` and `CHANGELOG.md` (`11:41`) forbid running alongside Dayframe.
   - **Fix:** Replaced with a check for `/Applications/Dayframe.app` and a warning if `/Applications/Dayflow.app` is present; updated `Briefing/uninstall.sh` message.
3. **`FIND-003` & `FIND-004` (`build-and-install.sh`):** Used coarse integer `df -g` (truncating e.g. `2.9 GB` to `2`), lacked `DAYFRAME_LOW_DISK_OK=1` support, did not sync `Briefing/dist` to `~/Briefing/app/dist`, and copied `Keepalive/local.dayframe.keepalive.plist` without `mkdir -p "$HOME/Library/LaunchAgents"`.
   - **Fix:** Aligned disk check with `check.sh` (`df -m`, `< 3000` MB, `DAYFRAME_LOW_DISK_OK=1` with `>= 1000` MB), synced `Briefing/dist` to `~/Briefing/app/dist` when `~/Briefing/app` exists, and added `mkdir -p "$HOME/Library/LaunchAgents"`.
4. **`FIND-005` (`START-HERE.md`, `AGENTS.md`, `logs.sh`):** Removed deleted `Briefing/Companion.swift` from `START-HERE.md` Section 1 and Section 6 To-do, updated `WelcomeEventGateTests` reference to `StartOfDayTests`, and listed all 7 active `os.Logger` categories (`welcome, startofday, wallpaper, island, briefing, recording, usage`) in `logs.sh` and `AGENTS.md`.
5. **`FIND-006` (`Upstream/`):** Kept untouched per `START-HERE.md` layout contract.

### Additional Defects Found by Full-Codebase Inspection (`FIND-007` to `FIND-011`)
6. **`FIND-007` (`Briefing/install.sh` -> `~/Briefing/status.json`):** In `Briefing/briefing.py`, `JOBS["companion"]` has a 1-hour overdue timer (`hours = 1`). When the Companion orb ran prior to `16:30`, it wrote `"companion"` into `~/Briefing/status.json`. One hour after `16:30`, `briefing.py doctor` permanently reports `LATE companion` ("Some checks need attention").
   - **Fix:** In the `else` branch of `Briefing/install.sh` (when `Companion.swift` is absent), a 1-line Python command removes `"companion"` from `~/Briefing/status.json` so `doctor` reports `companion: never` (`ok: True`), while keeping `JOBS["companion"]` in `briefing.py` so `TestDoctor` in `test_hardening.py` continues to pass.
7. **`FIND-008` (`Briefing/tests/test_briefing.py`, `Briefing/tests/test_improve.py`):**
   - `test_commands_never_touch_the_real_mac` did not stub `b.is_mac = lambda: True` (unlike `test_no_shell_injection` in `test_hardening.py`), causing `DESKTOP_CALLS` to be empty on non-Darwin environments.
   - `test_dirty_repo_or_skips` used `improve_min_free_gb=10 ** 9`, which is smaller than `INT64_MAX` (`9.22e9` GB) on 64-bit virtual filesystems; updated to `10 ** 15`.
   - **Result:** All 95 Briefing unit tests pass (`Ran 95 tests ... OK`).
8. **`FIND-009` (`App/Dayflow/Views/UI/SettingsView.swift`, `SettingsProvidersTabView.swift`, `LocalModelPreset.swift`, `ProvidersSettingsViewModel.swift`):**
   - Clicking `Manage local model` or `Upgrade now` in `Settings -> Providers` opened `LocalModelUpgradeSheet(preset: .qwen3VL4B, ...)` (the old upstream `Qwen3-VL 4B` model) instead of `.qwen35Model4B` (`Qwen3.5 4B`), and `shouldShowUpgradeBanner` / `usingRecommendedLocalModel` checked `.qwen3VL4B`.
   - **Fix:** Updated those 4 places to `.qwen35Model4B` and changed the hardcoded `"Upgrade to Qwen3VL"` banner text to `"Upgrade to \(preset.displayName)"`.
9. **`FIND-010` (`Briefing/dashboard.html`, `Briefing/swiftbar-briefing.5m.sh`, `Briefing/README.md`):**
   - `Briefing/dashboard.html` Settings tab omitted `llm_backend` and `cli_model` from `GROUPS`/`LABELS` (dropping them into an unlabelled `"Other"` card as raw text inputs) and showed `"Activity appears here as Dayflow records it."` in the Today empty state.
   - **Fix:** Added `llm_backend` (with a `<select>` for `ollama`, `claude_cli`, `codex_cli`, `grok_cli`, `openai`) and `cli_model` to the `Briefing` settings card in `dashboard.html`, fixed the `"Dayframe"` empty-state text, and updated `swiftbar-briefing.5m.sh` and `Briefing/README.md`.
10. **`FIND-011` (`.githooks/pre-commit`):** Restored `.githooks/pre-commit` (`exec ./check.sh --staged`) which was omitted when the zip archive was created.

---

## Complete List of Changed / Added Files in `Dayframe-v2-changed-files.zip`

| File Path | Action |
| :--- | :--- |
| `Briefing/install.sh` | Updated (`FIND-001`, `FIND-002`, `FIND-007`) |
| `Briefing/uninstall.sh` | Updated (`FIND-002`) |
| `build-and-install.sh` | Updated (`FIND-003`, `FIND-004`) |
| `logs.sh` | Updated (`FIND-005`) |
| `.githooks/pre-commit` | Restored (`FIND-011`) |
| `AGENTS.md` | Updated (`FIND-005`) |
| `START-HERE.md` | Updated (`FIND-005`) |
| `CHANGELOG.md` | Updated (top entry under `## 2026-10-13 (Tue)`) |
| `Briefing/dashboard.html` | Updated (`FIND-010`) |
| `Briefing/swiftbar-briefing.5m.sh` | Updated (`FIND-010`) |
| `Briefing/README.md` | Updated (`FIND-010`) |
| `Briefing/tests/test_briefing.py` | Updated (`FIND-008`) |
| `Briefing/tests/test_improve.py` | Updated (`FIND-008`) |
| `App/Dayflow/Views/UI/SettingsView.swift` | Updated (`FIND-009`) |
| `App/Dayflow/Views/UI/Settings/SettingsProvidersTabView.swift` | Updated (`FIND-009`) |
| `App/Dayflow/Core/AI/LocalModelPreset.swift` | Updated (`FIND-009`) |
| `App/Dayflow/Views/UI/Settings/ProvidersSettingsViewModel.swift` | Updated (`FIND-009`) |
| `docs/audits/2026-10-13T2232Z/AUDIT_CONTEXT_LOG.md` | Created (Audit Context Log) |
| `docs/audits/2026-10-13T2232Z/RECOMMENDATIONS.md` | Created (Recommendations & V2 Decisions) |
| `docs/audits/2026-10-13T2232Z/FINAL_SUMMARY.md` | Created (Final Handoff Summary) |
| `CLAUDE_INSTRUCTIONS.md` | Created (Claude handoff guide) |

---

## Step-by-Step Verification Commands for Claude on the Mac

```bash
cd ~/Documents/Projects/Dayframe

# 1. Unzip the changed files into the repo
unzip -o ~/Downloads/Dayframe-v2-changed-files.zip

# 2. Ensure executable bits are set on scripts and hooks
chmod +x build-and-install.sh check.sh logs.sh .githooks/pre-commit Briefing/install.sh Briefing/uninstall.sh Briefing/swiftbar-briefing.5m.sh

# 3. Run the fast clean-code gate (CHANGELOG, swift-format, Web tsc/Prettier/Vitest, Briefing 95 unittests)
./check.sh

# 4. Optional: if >= 1 GB free disk, also build Dayframe.app and run the 251 Xcode unit tests
DAYFRAME_LOW_DISK_OK=1 ./check.sh --app

# 5. Re-install Briefing so ~/Briefing/app gets the updated dashboard.html, tests, and cleaned status.json
cd Briefing && ./install.sh --check && ./install.sh && cd ..
python3 ~/Briefing/app/briefing.py doctor
```
