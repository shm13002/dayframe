# 09 — Prioritized Roadmap

| Order | Item | Impact | Effort | Risk | Dependencies | Status |
|---|---|---|---|---|---|---|
| **1 (v1.3)** | **Slice 1 (`FEAT-V13-001`):** Notch Pill `"Resume <project>?"` card + preemptive notice queue fix (`FIND-V13-001`, `FIND-V13-002`) | High | Low | Low | `BriefingNotice.swift`, `NotchPillView.swift`, `IslandController.swift`, `briefing.py` | **Implemented & Verified** |
| **2 (v1.3)** | **Slice 2 (`FEAT-V13-002`):** Hermetic in-process HTTP test transport for `Briefing/tests/` (`FIND-V13-003`) | High | Low | Low | `Briefing/tests/mocks.py`, `test_briefing.py`, `test_hardening.py` | **Implemented & Verified** |
| **3 (v1.3)** | **Slice 3 (`FEAT-V13-003`):** Application Evolution Engine & Evolution Center UI + `⋯` menu navigation (`FIND-V13-004`, `FIND-V13-005`) | High | Medium | Low | `Briefing/improve.py`, `Briefing/dashboard.html`, `BriefingView.swift`, `briefing-page.tsx` | **Implemented & Verified** |
| **4 (v1.4 Next)** | **Native SwiftUI Unit Test for `IslandController` Queue Preemption:** Extract notice queue preemption policy into a pure `BriefingNoticeQueue` value type so `check.sh --app` tests preemption without instantiating `NotchPillPanel`. | Medium | Low | Low | `App/Dayflow/Island/BriefingNotice.swift`, `BriefingNoticeTests.swift` | **Proposed (Next Iteration)** |
| **5 (v1.4+)** | **Grok CLI Vision Image Input (`--prompt-json`):** Test and enable screenshot image blocks for Grok timeline transcription once the owner completes `~/.grok/bin/grok login`. | Medium | Low | Low | Owner interactive login (`~/.grok/bin/grok login`) | **Blocked (User-Gated)** |
