# Iteration v1.3-001 — Proposal

- **Iteration ID:** `v1.3-001`
- **Authority Level:** Delegated **L2** (Low-risk, reversible changes with unit tests).
- **Objectives:**
  1. Complete the Notch Island notice migration by moving the `"Resume <project>?"` wake dialog (`offer_resume` in `Briefing/briefing.py`) into a native `.resume` notch card (`BriefingNotice.swift`, `NotchPillView.swift`, `IslandController.swift`) and fixing the unread `.brief` queue starvation bug (`FIND-V13-001`, `FIND-V13-002`).
  2. Make `Briefing/tests/` hermetic in zero-network sandboxes via an in-process HTTP fallback in `Briefing/tests/mocks.py` (`FIND-V13-003`).
  3. Upgrade `Briefing/improve.py` and `Briefing/dashboard.html` into the bounded **Application Evolution Engine & Evolution Center** (explicit state machine, L0 Audit-only mode, priority ranking formula, notch telemetry, rejected-proposal deduplication, and `⋯` menu navigation in `BriefingView.swift` and `briefing-page.tsx`) (`FIND-V13-004`, `FIND-V13-005`).
