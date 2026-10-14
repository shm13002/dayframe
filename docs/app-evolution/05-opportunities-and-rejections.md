# 05 — Opportunities and Rejections

## 1. Ranked Opportunities

| Opportunity | Category | Priority Score | Decision | Payoff |
|---|---|---|---|---|
| **Notch Pill `"Resume <project>?"` Card & Preemptive Notice Queue** | **Essential** | `2.40` | **Implemented in v1.3** | Eliminates the last jarring gray AppleScript dialog on wake and prevents 3-hour unread briefings from starving session-goal/resume prompts. |
| **Bounded Application Evolution Engine & Evolution Center UI** | **Essential** | `2.10` | **Implemented in v1.3** | Gives the owner an auditable L0/L1/L2 improvement control panel with explicit state transitions, priority scoring, and one-click rollback. |
| **Hermetic In-Process HTTP Test Transport (`mocks.py`)** | **High-value** | `1.85` | **Implemented in v1.3** | Makes all 104 Python unit tests pass in zero-network sandboxes and restricted CI environments without changing production code. |
| **Direct Evolution Center & Privacy Access from Dayframe `⋯` Menu** | **High-value** | `1.60` | **Implemented in v1.3** | Connects the native/React Briefing screen directly to `#/improve` and `#/privacy` in one click. |
| **Grok CLI Vision Image Input (`--prompt-json`)** | **Later (Blocked on User Login)** | `0.90` | **Deferred (`needs-info`)** | Requires interactive `~/.grok/bin/grok login` by the owner before live CLI image block testing can run. |

## 2. Explicit Rejections

| Rejected Proposal | Reason for Rejection |
|---|---|
| **Multi-Agent LLM Orchestrator for `improve.py`** | Violates Master Prompt §7 & §8.1 ("Begin with a simple orchestrator and add separate agents only if the evaluated benefit exceeds coordination overhead") and `ADR 0004` (16 GB RAM budget with local 4B model). |
| **Moving `~/Library/Application Support/Dayflow/` to `Dayframe/`** | Violates `ADR 0007`; would break `briefing.py` read-only DB sharing and orphan historical recordings. |
| **Changing Code Signing from Ad-Hoc `local.dayframe.app`** | Violates `ADR 0002`; would invalidate macOS TCC Screen Recording permission across rebuilds. |
| **Deleting `replay_companion` / `/api/companion` Backend Endpoints** | Would break 15+ existing unit tests in `test_briefing.py`, `test_improve.py`, and `test_hardening.py` with zero user-facing benefit. |
