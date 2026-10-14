# 13 — Next Iteration Plan (`v1.4-001`)

## Objective
Extract the Notch Island notice queue preemption and ordering state machine from `IslandController.swift` into a pure, value-typed `BriefingNoticeQueue` struct in `App/Dayflow/Island/BriefingNotice.swift` with direct unit tests in `App/DayflowTests/BriefingNoticeTests.swift`.

## Why This Slice Next
- Follows `AGENTS.md` Rule #2 ("Logic that decides something lives in a pure type with unit tests at its interface").
- Allows deterministic unit testing of multi-notice wake sequences (`.brief` → `.resume` → `.ask` → `.peek` → `.brief` restoration) without needing a live `NotchPillPanel` window.

## Acceptance Criteria
1. `BriefingNoticeQueue` is a pure Swift struct with ` mutating func enqueue(_ notice: BriefingNotice, currentMode: NotchPillModel.Mode)` and `mutating func finishCurrent() -> BriefingNotice?`.
2. Unit tests in `BriefingNoticeTests.swift` verify:
   - Newer `.brief` replaces unread `.brief`.
   - `.resume` and `.ask` preempt a passive `.brief` (`currentMode != .notice`) and restore the unread `.brief` after completion.
   - `.brief` actively open in `.notice` mode is not yanked out from under the user's pointer while reading.
3. `./check.sh --app` passes with 0 warnings and 0 failures.
