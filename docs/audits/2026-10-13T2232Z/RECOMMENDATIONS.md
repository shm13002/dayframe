# Recommendations & V2 Decisions

## 1. Decision Summary
- **Highest-Value Actions Implemented Now:**
  1. Fix `Briefing/install.sh` so it no longer crashes on the deleted `Companion.swift` file, cleans up any stale companion LaunchAgent/binary, and removes any stale `"companion"` entry from `~/Briefing/status.json` so `briefing.py doctor` stays healthy (`REC-001`).
  2. Remove the `brew install --cask dayflow` step from `Briefing/install.sh` so reinstalling Briefing never reintroduces the conflicting upstream `Dayflow.app` (`REC-002`).
  3. Upgrade `build-and-install.sh` to use MB-resolution disk checks (`df -m`), honor `DAYFRAME_LOW_DISK_OK=1`, sync `Briefing/dist` to `~/Briefing/app/dist`, and create `~/Library/LaunchAgents` before copying the keep-alive plist (`REC-003`).
  4. Synchronize `START-HERE.md`, `AGENTS.md`, `logs.sh`, `.githooks/pre-commit`, and `CHANGELOG.md` with the current codebase (`REC-004`).
  5. Fix the `Briefing/tests/` cross-platform portability bugs (`test_commands_never_touch_the_real_mac` and `test_dirty_repo_or_skips`) so all 95 Python unit tests pass on both macOS and Linux (`REC-007`).
  6. Fix the `LocalModelUpgradeSheet` and preset checks in `App/Dayflow/` so `Manage local model` / `Upgrade local model` targets `Qwen3.5 4B` (`.qwen35Model4B`) rather than legacy `Qwen3-VL 4B` (`REC-008`).
  7. Add `llm_backend` (`<select>`) and `cli_model` to the `Briefing` settings card in `Briefing/dashboard.html` and align remaining user-facing `Dayframe` strings (`REC-009`).
- **Strengths to Retain Unchanged:**
  - Ad-hoc code signing with fixed designated requirement `identifier "local.dayframe.app"` (`ADR 0002`).
  - `RecordingWatchdog`, SIGTERM video chunk closure (`FrameStore.finishCurrentSegment`), `BatchRunGate`, and `local.dayframe.keepalive`.
  - `run_on_mac()` desktop side-effect tripwire in `Briefing/briefing.py` and `Briefing/tests/mocks.py`.
  - `.githooks/pre-commit` and `./check.sh --staged` quality gate.
- **Changes Not Justified by Evidence:**
  - Ripping out `/api/companion` and `replay_companion` from `Briefing/briefing.py` and `Briefing/improve.py` (would break 15+ existing unit tests in `test_briefing.py`, `test_improve.py`, and `test_hardening.py` with zero user benefit).

## 2. Prioritized Recommendations (`REC-001` to `REC-009`)

| ID | Linked IDs | Problem | Proposed Action | Status |
| :--- | :--- | :--- | :--- | :--- |
| `REC-001` | `FIND-001`, `FIND-007`, `FEAT-012`, `FEAT-016`, `EVID-002`, `EVID-007` | `Briefing/install.sh` aborts at line 54 because `Briefing/Companion.swift` was removed, leaves `PORT` unbound, and leaves stale `"companion"` state in `~/Briefing/status.json` | Copy only active Briefing files, define `PORT` unconditionally, wrap Companion compilation in `if [[ -f "$SRC/Companion.swift" ]]`, and strip stale `"companion"` state from `status.json` when absent | **Implemented & Verified** |
| `REC-002` | `FIND-002`, `FEAT-001`, `FEAT-012`, `EVID-003` | `Briefing/install.sh` checks for and installs upstream `Dayflow.app` via Homebrew, violating `ADR 0007` | Check for `/Applications/Dayframe.app` instead, warn if `/Applications/Dayflow.app` is installed, and update `Briefing/uninstall.sh` | **Implemented & Verified** |
| `REC-003` | `FIND-003`, `FIND-004`, `FEAT-009`, `EVID-004` | `build-and-install.sh` truncates free disk space (`df -g`), lacks `DAYFRAME_LOW_DISK_OK=1`, skips syncing `Briefing/dist`, and omits `mkdir -p ~/Library/LaunchAgents` | Use `df -m` (`< 3000` MB) with `DAYFRAME_LOW_DISK_OK=1` (`>= 1000` MB), copy `Briefing/dist` to `~/Briefing/app/dist`, and `mkdir -p "$HOME/Library/LaunchAgents"` | **Implemented & Verified** |
| `REC-004` | `FIND-005`, `FIND-011`, `EVID-006`, `EVID-011` | `START-HERE.md`, `AGENTS.md`, and `logs.sh` contain stale `Companion.swift` / `WelcomeEventGateTests` references and miss 3 logger categories; `.githooks/pre-commit` missing from zip | Update `START-HERE.md`, `AGENTS.md`, `logs.sh`, and `CHANGELOG.md`, and restore `.githooks/pre-commit` | **Implemented & Verified** |
| `REC-005` | `CONN-004`, `FEAT-010` | Grok CLI timeline transcription currently uses Vision OCR text-only because headless mode rejected image flags before sign-in | Defer live image flag testing until user runs `~/.grok/bin/grok login` | **Deferred (User-Gated)** |
| `REC-006` | `FIND-006` | `Upstream/` directory contains original Dayflow release scripts and duplicate test files | Keep untouched as reference per `START-HERE.md` layout contract | **Deferred / Kept by Design** |
| `REC-007` | `FIND-008`, `FEAT-012`, `FEAT-014`, `EVID-008` | `test_commands_never_touch_the_real_mac` and `test_dirty_repo_or_skips` fail on non-Darwin / 64-bit virtual filesystems | Stub `b.is_mac = lambda: True` in `test_commands_never_touch_the_real_mac` and use `10 ** 15` in `test_dirty_repo_or_skips` | **Implemented & Verified (95/95 pass)** |
| `REC-008` | `FIND-009`, `FEAT-002`, `FEAT-010`, `EVID-009` | `Settings -> Providers -> Manage local model` sheet and preset checks still reference `.qwen3VL4B` instead of `.qwen35Model4B` | Update `SettingsView.swift`, `SettingsProvidersTabView.swift`, `LocalModelPreset.swift`, and `ProvidersSettingsViewModel.swift` to `.qwen35Model4B` | **Implemented & Verified** |
| `REC-009` | `FIND-010`, `FEAT-012`, `EVID-010` | `Briefing/dashboard.html` Settings omits `llm_backend` and `cli_model` from the `Briefing` card and shows `"Dayflow"` in empty state | Add `llm_backend` `<select>` and `cli_model` to `dashboard.html` Settings and update `Dayframe` strings in `dashboard.html`, `swiftbar-briefing.5m.sh`, and `README.md` | **Implemented & Verified** |

## 3. Alternatives and Tradeoffs
- **`REC-001` (Companion Removal in Installer & Doctor):**
  - *Keep as-is:* `Briefing/install.sh` remains broken (`exit 1` on line 54) and `briefing.py doctor` reports `LATE companion`.
  - *Small targeted change (Selected):* Make `Companion.swift` conditional in `Briefing/install.sh`, clean up stale companion artifacts, and pop `"companion"` from `~/Briefing/status.json` when absent.
  - *Larger replacement (Rejected):* Delete all companion endpoints and replay logic from `briefing.py`, `improve.py`, `dashboard.html`, and `Briefing/tests/` — high churn and breaks 15+ existing unit tests.
- **`REC-002` (`Dayflow.app` vs `Dayframe.app` in `Briefing/install.sh`):**
  - *Keep as-is:* Running `./Briefing/install.sh` reinstalls `Dayflow.app` via Homebrew, risking database corruption (`ADR 0007`).
  - *Small targeted change (Selected):* Check for `/Applications/Dayframe.app` and warn if `/Applications/Dayflow.app` is present.

## 4. Evidence and Uncertainty
- All implemented recommendations (`REC-001`..`REC-004`, `REC-007`..`REC-009`) are backed by direct source inspection and test execution (`EVID-001` through `EVID-011`).
- `REC-005` (Grok image support) depends on live CLI behavior after `~/.grok/bin/grok login` and cannot be settled offline.

## 5. Execution Criteria
- `./check.sh` must exit 0 (`check.sh: all clean.`).
- `python3 -m unittest discover -s tests -v` in `Briefing/` must exit 0 (`Ran 95 tests ... OK`).
- `./Briefing/install.sh --check` and `./Briefing/install.sh` must complete with exit code 0 when `Briefing/Companion.swift` is absent.

## 6. V2 Scope
- **Implement Now:** `REC-001`, `REC-002`, `REC-003`, `REC-004`, `REC-007`, `REC-008`, `REC-009`.
- **Defer (User-Gated):** `REC-005` (Grok image testing after `grok login`), first-run intro video rebranding.
- **Explicitly Exclude:** Rewriting `briefing.py` or `improve.py` companion replay history; changing `local.dayframe.app` signing requirement (`ADR 0002`); moving `~/Library/Application Support/Dayflow/` (`ADR 0007`).

## 7. Tooling Decisions
- **Keep:** `./check.sh` + `.githooks/pre-commit`, `xcrun swift-format`, Prettier, Vitest, Python `unittest`, and `logs.sh`.
- **Do Not Install:** External orchestration layers (`Paperclip`, `Hermes Agent`, `Codebase Memory MCP`) — unnecessary overhead on a disk-constrained single-user Mac.

## 8. Product Opportunities (Separate from Defect Corrections)
- **Automatic `Dayflow.app` Conflict Guard at Launch:** `AppDelegate` could check `NSWorkspace.shared.runningApplications` for `teleportlabs.com.Dayflow` at startup and offer to quit it automatically to enforce `ADR 0007` in code as well as docs.
