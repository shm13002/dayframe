# 07 — Architecture and Performance Plan

## 1. Resource & Performance Guardrails
- **Memory & Model Context (`ADR 0004`):** Local `qwen3.5:4b` runs on a 16 GB Mac with a 4,096-token context window and `reasoning_effort: "none"` (~6s response time vs. 20–46s with thinking enabled). `num_ctx` is never overridden so Ollama never reloads the model mid-session.
- **WebGL / Canvas Rendering (`ADR 0005`):** Notch Island and Welcome shows avoid CPU-bound WebKit SVG filters and log measured FPS (`58–60 fps`).
- **Disk Space Circuit Breakers:** `check.sh`, `build-and-install.sh`, and `Briefing/improve.py` all enforce minimum free disk space (`3,000 MB` for clean Xcode builds, `1,000 MB` with `DAYFRAME_LOW_DISK_OK=1`, and `improve_min_free_gb: 2` for nightly evolution runs).
- **Database Isolation (`ADR 0007`):** `Dayframe.app` owns read/write access to `~/Library/Application Support/Dayflow/chunks.sqlite`; `Briefing/briefing.py` connects strictly with `file:...?mode=ro` (`uri=True`, 5s timeout).

## 2. v1.3 Engineering Improvements
- **Zero New External Dependencies:** All v1.3 enhancements use existing Swift/SwiftUI, React/TypeScript, and Python 3 standard-library primitives.
- **In-Process Test Server Fallback (`Briefing/tests/mocks.py`):** Eliminates kernel socket dependency when running inside restricted sandboxes, executing all 104 Python unit tests in ~35 seconds with zero network egress.
- **Bounded Evolution Storage:** `~/Briefing/improve/proposals.json` is capped at the 100 most recent proposals, `transitions.jsonl` and `runs.jsonl` append compact single-line JSON records, and `telemetry.jsonl` rotates automatically at 5 MB (`TELEMETRY_MAX_BYTES`).
