# 04 — Feature-by-Feature Evolution Matrix

| Feature | Decision | Rationale & v1.3 Action | Verification Test |
|---|---|---|---|
| **Continuous Screen Recording & Watchdog** (`ScreenRecorder`, `RecordingWatchdog`) | **Keep** | Rock-solid, stable signing (`ADR 0002`), SIGTERM chunk closure, and 30s frame watchdog. Do not disturb. | Existing `RecordingWatchdogTests` |
| **Timeline Batch Analysis & Providers** (Qwen, Claude, Codex, Grok) | **Keep** | Keyless CLI architecture (`ADR 0003`) and Qwen `reasoning_effort: "none"` (`ADR 0004`) work cleanly. | `ClaudeCLIExecutionProfileTests`, `GrokCLITests`, `test_cli_backend.py` |
| **Notch Island & Briefing Notices** (`NotchPillView`, `BriefingNotice`, `IslandController`) | **Extend & Repair** | Extended in v1.3 with `.resume` notice card so `"Resume <project>?"` comes out of the notch instead of a gray system dialog (`FIND-V13-001`), and repaired queue preemption so unread briefings never starve interactive prompts (`FIND-V13-002`). | `test_notch.py` (8 tests), `BriefingNoticeTests.swift` |
| **Start of Day & Welcome Show** (`WelcomeController`, `StartOfDay`, `WallpaperManager`) | **Keep** | Per-login-session gate (`ADR 0006`) and 58–60 fps WebGL/Canvas rendering (`ADR 0005`) are verified. | `WelcomeTests.swift` |
| **Briefing Tab (React & Native SwiftUI)** (`BriefingView.swift`, `briefing-page.tsx`) | **Extend** | Added **Evolution Center** (`improve`) and **Privacy & cleanup** (`privacy`) to the `⋯` More menu on both surfaces (`FIND-V13-004`). | `swift-format` + parity check |
| **Companion Orb (`Companion.swift`)** | **Retire (Completed in v1.1)** | Removed per owner request; `replay_companion` retained in `improve.py` for offline test coverage without running any desktop orb process. | `test_hardening.py` |
| **Self-Improvement Loop (`improve.py` + `dashboard.html`)** | **Redesign & Extend into Evolution Center** | Upgraded to full **Application Evolution Engine** with 19-state pipeline, L0 Audit-Only mode, transparent priority scoring, notch notice health metrics, and rejected-proposal deduplication (`FIND-V13-005`). | `test_improve.py` (`test_evolution_engine_audit_mode_transitions_and_deduplication`) |
