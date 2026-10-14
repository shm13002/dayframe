# 06 — Design System and Experience

## 1. Visual Foundations (Observed & Preserved)
- **Dual-Surface Coherence:**
  - **Main App & Briefing Tab (`App/` & `Web/`):** Uses `Instrument Serif` (20–30pt display headings), `Figtree` (11–17pt body/controls), glassmorphic card shells (`BriefingCardShell` / `GlassCard`), and six semantic palettes (`Original`, `Lagoon`, `Lavender`, `Matcha`, `Rose`, `Ember`) defined in `DayframePalette.swift` and pinned to `Web/src/theme/palettes.ts` by unit test.
  - **Notch Pill (`NotchPillView.swift`):** Uses fixed hardware-notch black (`#000000`) with `PillInk` neutral tokens (`#1C1C1E` surface, `#2A2A2E` track, `#D0D0D4` body, `#8A8A8E` muted) and the active palette's dynamic `accentHex` for the focus arc, unread Jarvis eyes, and step badges.
  - **Advanced Dashboard & Evolution Center (`Briefing/dashboard.html`):** Uses an 8pt spacing grid (`--s1` to `--s7`), type scale `12/13/14/16/20/28px`, AA contrast tokens in both `[data-theme=dark]` and `[data-theme=light]`, and `prefers-reduced-motion: reduce` support.

## 2. v1.3 UX & Interaction Upgrades
1. **Notch Resume Card (`NotchPillView.swift` → `resumeCard`):**
   - **Before (v1.2):** `offer_resume()` invoked `osascript -e 'display dialog "Resume <project>?..."'`, interrupting the user with a system modal right after the quiet notch briefing peek.
   - **After (v1.3):** Arrives as a one-line quiet peek (`Resume <project>? · Apps: ...`) below the notch; clicking opens a 420pt-wide black notch card with header `"Resume workspace"`, the project's apps/links/files in `PillInk.body`, a primary **Resume** pill button, and a subtle **Not now** button.
2. **Preemptive Notice Queue (`IslandController.swift`):**
   - Interactive notices (`.ask`, `.resume`) and transient nudges (`.peek`) now preempt a passive unread `.brief` notice (re-queuing the `.brief` right behind them), ensuring the user never misses a time-sensitive prompt while keeping Jarvis's eyes tinted until the briefing is read.
3. **Evolution Center Control Panel (`Briefing/dashboard.html` & `BriefingView.swift`):**
   - Accessible directly from the Briefing tab's `⋯` menu (**Evolution Center**) or shortcut `I` in the dashboard.
   - Displays a top **Pipeline State & Authority Mode** bar (`IDLE`, `OBSERVING`, `ANALYZING`, `PROPOSING`, `REVIEWING`, `VERIFYING`, `APPROVAL_PENDING`, etc.), an interactive **Mode Selector** (`Audit (L0)`, `Guided (L0–L1)`, `Controlled autonomous (L2)`, `Scheduled`), an **Audit only (L0)** button, a **Run guided cycle** button, a **Candidate Backlog** ranked by priority score, and collapsible **State Transitions** logs.
