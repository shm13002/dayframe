# Iteration v1.3-001 — Evaluation

| Metric / Criterion | Baseline (v1.2) | Target (v1.3) | Measured Result (v1.3) | Verdict |
|---|---|---|---|---|
| **Gray macOS dialogs during wake when Dayframe is open** | 1 (`"Resume <project>?"` dialog) | 0 (all wake prompts in notch pill) | **0** (`offer_resume` uses `notch("resume", ...)` with 3s fallback) | **Pass** |
| **Wake `.ask`/`.resume` starvation behind unread `.brief`** | Blocked for up to 3h | 0s delay (preempts passive `.brief`) | **0s delay** (`presentNotice` preempts passive `.brief` and re-queues it) | **Pass** |
| **Briefing unit tests in zero-network sandbox** | 5 import errors / 100 tests | 100% pass (104/104 tests) | **104/104 pass (`OK` in 35.1s)** | **Pass** |
| **Swift-format warnings on modified Swift files** | 0 | 0 | **0 warnings across all 5 files** | **Pass** |
| **Evolution Engine L0 Audit-only mode & state machine** | Not implemented | 19-state machine + L0 `run_audit()` with 0 file/branch edits | **Verified by `test_evolution_engine_audit_mode_transitions_and_deduplication`** | **Pass** |
