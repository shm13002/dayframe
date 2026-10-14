# 02 — Baseline and Evidence

## 1. Baseline Environment (Observed)
- **Baseline Version:** Dayframe `v1.2 (2026-10-13)` (`Dayframe-source.zip` at commit `03dc1b2cb92c2ba1e51cd71a5f59c1066d0bd6a4`, built from `3cba3c4`).
- **OS & Toolchains:** macOS (Darwin), Python `3.9.6` (`/usr/bin/python3`), `xcrun swift-format` (`602.0.0`), Node `v25.2.1` (`/opt/homebrew/bin/node`).
- **Disk Availability:** `13,791 MB` (~13.5 GB) free on `/System/Volumes/Data` (`df -m .`), well above the 3,000 MB threshold in `check.sh` and `build-and-install.sh`.

## 2. Baseline Verification Measurements

| Check / Suite | Command | v1.2 Baseline Outcome | Notes / Evidence |
|---|---|---|---|
| **Swift Style (Dayframe files)** | `xcrun swift-format lint --configuration .swift-format` | **0 warnings** on all Dayframe feature files (`Island/`, `Welcome/`, `Briefing/`) | 2 upstream-derived test files (`ProvidersSettingsViewModelTests.swift`, `TimeParsingTests.swift`) carried 10 pre-existing warnings allowed by `check.sh` |
| **Briefing Unit Tests (Host Terminal)** | `python3 -m unittest discover -s tests` | **100 tests, 0 failures** (recorded in `v1.2` `README.txt`) | **Failed in zero-network sandbox** (`5 errors`) due to unconditional `ThreadingHTTPServer(("127.0.0.1", 0))` socket bind (`FIND-V13-003`) |
| **Briefing Unit Tests (After v1.3 Hermetic Fix)** | `python3 -m unittest discover -s tests` | **104 tests, 0 failures** (`OK` in ~35s full suite) | Includes 3 new notch-resume tests + 1 new Evolution Engine state-machine/audit/deduplication test |
| **App Unit Tests (v1.2 Baseline)** | `./check.sh --app` | **259 tests (1 skipped), 0 failures** (recorded in `CHANGELOG.md` 22:19) | Extended in `BriefingNoticeTests.swift` with `testResumeNoticePeekAndConfirmation` and `resume-card` snapshot |
