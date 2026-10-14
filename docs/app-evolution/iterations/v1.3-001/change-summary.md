# Iteration v1.3-001 — Change Summary

1. **Notch Pill `"Resume <project>?"` Card & Preemptive Notice Queue (`FEAT-V13-001`):**
   - `Briefing/briefing.py` (`offer_resume`) now sends a `resume` notice to Dayframe's notch pill (`dayframe://notice?id=<id>`) and waits up to 3 seconds for `.ack` before falling back to the legacy AppleScript dialog.
   - `App/Dayflow/Island/BriefingNotice.swift`, `NotchPillView.swift`, and `IslandController.swift` render the `"Resume <project>?"` peek and card (**Resume** / **Not now**) and preempt passive unread `.brief` notices so interactive `.ask` and `.resume` prompts are shown immediately during `cmd_wake`.
2. **Application Evolution Engine & Evolution Center UI (`FEAT-V13-003`):**
   - `Briefing/improve.py` and `Briefing/dashboard.html` implement the 19-state Evolution Engine pipeline (`IDLE → OBSERVING → ANALYZING → PROPOSING → REVIEWING → BASELINING → IMPLEMENTING → VERIFYING → EVALUATING → APPROVAL_PENDING → MERGED/REJECTED/REVERTED → RECORDED → IDLE`), 4 authority modes (`audit`, `guided`, `controlled_autonomous`, `scheduled`), priority scoring, notch telemetry, and rejected-proposal deduplication.
   - `BriefingView.swift` and `Web/src/briefing/briefing-page.tsx` add **Evolution Center** and **Privacy & cleanup** to the `⋯` More menu.
3. **Hermetic Test Suite (`FEAT-V13-002`):**
   - `Briefing/tests/mocks.py`, `test_briefing.py`, and `test_hardening.py` automatically fall back to an in-process HTTP server when kernel socket binding is blocked, bringing the test suite to **104/104 passing tests**.
