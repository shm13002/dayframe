# Notch pill Resume card & non-starving notice queue
Status: done
Type: task

Move `offer_resume(cfg)` in `Briefing/briefing.py` to `notch("resume", ...)` with 3s fallback to the AppleScript dialog. Add `.resume` to `BriefingNotice.Kind`, `resumeCard` to `NotchPillView.swift`, and preempt passive unread `.brief` notices in `IslandController.presentNotice` so wake prompts never hang behind a 3-hour unread briefing.
