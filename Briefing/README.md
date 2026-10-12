# Dayflow Briefing (free, local, no API keys)

Turns [Dayflow](https://github.com/JerryZLiu/Dayflow)'s screen timeline into a **memory folder that keeps learning**,
gives you a **"where you left off" briefing** on wake/login, and can **delete recordings once they're distilled**.
Everything runs on your Mac via Ollama (localhost:11434). Dayflow's DB is opened **read-only**.

## What it does
| Job | When | Does |
|---|---|---|
| `wake` | login + every wake (30-min cooldown) | briefing from profile, goals, open loops, relevant projects, latest daily log; then asks your session goal |
| `checkin` | every 75 min (quiet 22:00–08:00) | "what are you working on / blockers?" |
| `distill` | every 45 min | new Dayflow cards + your answers → `memory/daily/`, then Ollama merges facts into the knowledge base |
| `nightly` | 23:00 | distill backlog, weekly rollup, recordings cleanup, reindex |
| `ask "…"` | on demand | answers from your memory (SQLite FTS5 search + Ollama), cites files |

## Memory folder `~/Briefing/memory/`
```
daily/YYYY-MM-DD.md     full chronological log: titles, summaries, detailed summaries, metadata, your notes
profile.md goals.md open-loops.md people.md patterns.md   curated, updated incrementally
projects/<slug>.md      per-project history, decisions, status, next steps
weekly/YYYY-Www.md      weekly rollups
index.sqlite            search index      .backups/  last 5 versions of every curated file
cleanup-report.md       what was / would be deleted
```
Raw daily logs are written before any AI step, so nothing is lost if Ollama is down (curation retries next run).
Curated files have size caps and refuse updates that would wipe most of the file.

## Recording cleanup (dry-run by default)
Dayflow stores 10-minute `.mp4` screen segments in `~/Library/Application Support/Dayflow/recordings/`.
Its own retention is **size-based** (Settings → storage limit, default 10 GB), not time-based.
This add-on deletes a recording only if **all** are true: inside that folder, not a DB/sqlite file or symlink,
older than `cleanup_min_age_hours` (24), every Dayflow reference belongs to a `completed` analysis batch,
and those batches' timeline cards are already distilled into your memory. The DB is never touched.
Check `memory/cleanup-report.md`, then set `"cleanup_enabled": true` in `~/Briefing/config.json`.
Note: deleted recordings can't be replayed or re-analyzed in Dayflow (its timeline text stays).
Alternative: lower Dayflow's own storage limit in its Settings.

## Install / use
```bash
unzip dayflow-briefing.zip && cd dayflow-briefing
./install.sh --check      # read-only preflight: python, CLT, Dayflow DB, Ollama, port, disk
./install.sh
python3 ~/Briefing/app/briefing.py doctor
python3 ~/Briefing/app/briefing.py brief --force
python3 ~/Briefing/app/briefing.py ask "what did I decide about the landing page?"
python3 ~/Briefing/app/briefing.py status
```
Then open Dayflow, grant Screen Recording, choose Ollama as provider.
Config `~/Briefing/config.json`: `model`, `speak`, `voice`, `cooldown_minutes`, `lookback_hours`,
`checkin_quiet_hours`, `memory_max_chars`, `cleanup_enabled`, `cleanup_min_age_hours`.
Default model by RAM: 8GB `qwen3.5:4b`, 16GB `qwen3.5:9b`, 24GB `gemma4:12b`, 32GB `gemma4:26b`,
36–64GB `qwen3.6:35b`, 96GB+ `gpt-oss:120b`. Logs: `~/Briefing/briefing.log`.

## Uninstall
`./uninstall.sh` (keeps memory) or `./uninstall.sh --purge`. Removes all LaunchAgents, the `~/.wakeup` block, the SwiftBar
link and `~/Briefing/app`; Ollama, Dayflow and sleepwatcher stay installed. Revoke the companion's permissions in
System Settings → Privacy & Security if you like (the entries just go stale otherwise).

## Troubleshooting (first Mac test)
Start with `python3 ~/Briefing/app/briefing.py doctor`; every red line says what to do. Jobs exit with code 1 on a real
failure (LLM or Dayflow error), so `launchctl print gui/$(id -u)/com.dayflowbriefing.distill` shows `last exit code`.

| Symptom | Cause / fix |
|---|---|
| `xcrun: error` / python prompts to install tools | `xcode-select --install`, then rerun `./install.sh`. System python 3.9 is supported; no pip packages are needed. |
| doctor: *Dayflow database not found* | Open Dayflow once and let it record; if it lives elsewhere set `dayflow_db` in `~/Briefing/config.json`. |
| doctor: *Dayflow schema changed* | Dayflow updated its DB; nothing is written to it (read-only). Send the message from doctor; briefings keep working from memory. |
| doctor: *Ollama not reachable* / *model not pulled* | `open -a Ollama`, then `ollama pull <model>` (the CLI is in `/Applications/Ollama.app/Contents/Resources` if not on PATH). |
| Jobs work in Terminal but not from launchd | Re-run `install.sh`: plists set PATH to `/opt/homebrew/bin:/usr/local/bin:…` (Apple Silicon + Intel) and are checked with `plutil -lint`. |
| No briefing on wake | sleepwatcher missing: `brew install sleepwatcher && brew services start sleepwatcher`. Login briefing still works. |
| Dashboard won't load | doctor: *port 8765 in use* → set `dashboard_port` in config and rerun install (the job waits 60 s between retries). |
| Dialogs / "osascript wants to control…" | Allow once (System Settings → Privacy & Security → Automation). Denying only disables that dialog/resume feature. |
| Orb never appears / no window text | Grant **Accessibility** to `BriefingCompanion` (required); **Screen Recording** is only for the OCR fallback; mic/speech only for push-to-talk. After granting, `launchctl kickstart -k gui/$(id -u)/com.dayflowbriefing.companion`. |
| Companion didn't build | Needs Xcode CLT + macOS 14+. The rest works without it. It's built locally, so Gatekeeper/quarantine doesn't apply (install also clears the flag). |
| First run looks empty | Normal: memory fills after the first distill (every 30 min) and nightly run; Improvements needs ~30 companion outcomes before proposing anything. |

## v3: dashboard, coach, debrief & more (all local, no keys)

| Feature | How |
|---|---|
| **Dashboard** | http://127.0.0.1:8765 (LaunchAgent `dashboard`, localhost only, Host/Origin checked). Today's briefing, timeline, goals, open loops you can check off, project pages, focus heatmap, weekly report, ask box, privacy, settings. |
| **Menu bar** | `brew install --cask swiftbar`, pick a plugin folder, rerun `install.sh` (links `swiftbar-briefing.5m.sh`). |
| **Raw logs are the primary record** | `memory/daily/.YYYY-MM-DD.jsonl` (kept forever) → rendered `daily/YYYY-MM-DD.md` with line ids `#N`. Curated notes cite them as `[2026-10-12#3]`. |
| **Ask your past** | `briefing.py ask "..."`. Hybrid search: SQLite FTS5 + `nomic-embed-text` embeddings (cached in `index.sqlite`), merged with reciprocal rank fusion. Falls back to FTS only. |
| **Resume** | On wake, after the briefing, a dialog offers to reopen the last project's apps (AppleScript `activate`), links and files (`open`). Nothing opens unless you click **Resume**. Also `briefing.py resume`, the dashboard button and the menu bar. |
| **Debrief** | 6pm (`debrief_hour`): spoken prompt with `say`, reply in a dialog (Handy or macOS Dictation work there), or `debrief_use_whisper: true` records 60s with ffmpeg + whisper.cpp. |
| **Distraction coach** | After each distill: if ≥`coach_threshold_minutes` of distraction categories in the last hour, you get a gentle notification (90-min cooldown) with your best focus hours. |
| **Auto to-dos** | "I need to / follow up with / remember to…" in check-ins, debriefs, meetings and cards, plus LLM-detected loops, go to `todos.json` / `open-loops.md`. They are deduplicated, closed when the work is done, and shown in briefings. |
| **Project autopilot** | `projects/<slug>.md` = LLM-curated history/decisions + an auto block with time per day, sessions, files, links and apps. |
| **Weekly "You" report** | Sunday 18:30: time vs goals, changes vs last week, wins, best hours, one experiment. |
| **Meetily** | Reads `~/Library/Application Support/com.meetily.ai/meeting_minutes.sqlite` read-only (meetings, transcripts, summaries, notes, action items). |
| **Privacy** | `blocklist` (apps/sites/keywords): matching items are never written. `forget --from D --to D [--rebuild]` purges raw logs, notes, to-dos, cited curated lines, backups and the index. Dayflow's own DB is not touched. |
| **LocalClicky hook** | `briefing.py context [--json]` or `GET http://127.0.0.1:8765/api/context` → goal, recent activity and open loops. Add it to a screen assistant's system prompt, e.g. `curl -s localhost:8765/api/context`. |
| **Phone** | `phone_push`: `ntfy` (set a long random `ntfy_topic`. Public ntfy.sh topics can be read by anyone who guesses the name, so self-host for privacy) or `imessage` (`imessage_to` = yourself). Off by default. Turn on `push_briefing` to send briefings to the phone. |

## v4: Automate-my-work + next-move companion

**Automations tab** (dashboard → ⚡, or the CLI): `briefing.py automations` mines the raw daily logs from the last 4 weeks for
repeated app/site sequences (2 to 4 steps, found on 3+ days) and repeated routines. Each one shows its usual hour and weekdays and is ranked by estimated minutes saved per week. These are rough heuristics: about 1.5 min per step, or 20% of a routine's time.
- **Draft**: the local model writes an AppleScript/JXA, shell, Playwright or Shortcuts-steps script to `~/Briefing/automations/`.
- **Dry-run** never executes the script. It runs a compile/syntax check (`osacompile`, `bash -n`, shellcheck, `py_compile`) plus a safety lint for things like rm -r, sudo, curl|sh or sending messages, and lists the apps and URLs it would touch.
- **Approve** stores a hash of the file. **Run** works only for approved, unchanged files and needs an explicit confirm (`run-automation ID --yes`). Editing the file revokes approval. Accepts, rejections and runs are kept in the history.

**Next-move companion** (`Companion.swift`, built by install.sh with `swiftc`; needs `xcode-select --install`):
a small floating bubble near the cursor shows the predicted next intent with up to 3 one-tap actions (open an app, URL or file, run an *approved* automation, add a to-do).
- **Hotkeys**: ⌃⌥Space accepts the first action (or asks now if nothing is showing), ⌃⌥X dismisses, ⌃⌥T opens a box for push-to-talk via Dictation/Handy that asks your memory.
- **Voice**: set `nextmove_speak: true` to speak via `say`.
- **Pointing**: highlights the target app's window. Dock icons can't be targeted.
- **Prediction**: runs on app switch and every minute, after the gate below. The model sees the last ~10 cards, your profile, open loops, learned routines and approved automations. It must return an intent or null. Actions are checked against that context, and made-up apps, files or automations are dropped.
- **Gate (should I interrupt?)**: no suggestions in quiet hours, after 5+ min idle, or during deep focus (25+ min of continuous non-distraction work; an app switch is still allowed). There's a 10-min cooldown that doubles with each dismiss in a row (up to ×16). Suggestion types you usually dismiss (fewer than 20% accepted over 5+ tries) need 0.8 confidence instead of 0.55.
- **API for LocalClicky and others**:
  - `GET /api/next-move?trigger=app_switch&app=Figma` returns the prediction.
  - `POST /api/next-move/feedback {"id","outcome":"accept"|"dismiss","action":0}` records your choice.
  - `GET /api/next-move/stats` returns the learning stats.

## Development & tests
`python3 -m unittest discover -s tests -v` (stdlib only; runs on Linux or macOS). `tests/mocks.py` provides:
- an in-process fake Ollama (modes: ok, garbage, fenced JSON, empty),
- a realistic 6-week Dayflow DB with unicode titles, soft-deleted cards and blocklisted items,
- a Meetily DB.

The 29 tests cover:
- distill and backlog draining, citations, privacy, forget
- cleanup safety, malformed or empty model output, Ollama down, missing DB, schema changes, empty DB, 5,000-card days
- automations lifecycle, next-move gating and rate limits
- every CLI command
- the HTTP API (Host/Origin/content-type checks, 400 on bad input)

Dashboard keyboard shortcuts: `1`–`0` switch tabs, `/` jumps to Ask, `Esc` closes the mobile "More" sheet. Theme follows the system; toggle in the sidebar or with `?theme=light|dark`.

## v5: Anticipatory companion (Clicky-style)

`Companion.swift` is now a small glowing orb that trails your cursor. It stays quiet until you look stuck, then pulses. Hover it or hold **⌃⌥** to open a frosted card with 1–3 predicted questions, an input prefilled with the best guess as ghost text (**Tab** accepts, **↩** asks), hold-to-talk (on-device speech), and a streamed answer. An animated pointer highlights the part of the screen the answer is about.

- **Works in any context.** Modes: studying, coding, writing, design, spreadsheets, email, research, shopping, admin/forms, video, meetings, plus unknown (falls back to "what are you trying to do here?"). The mode is detected from the app, the window title/URL and the screen text. Each mode has its own stuck-signal weights, question style and answer style:
  - hints ladder for study;
  - a code fix for coding;
  - a rewrite for writing;
  - a formula for spreadsheets;
  - pointer-guided steps for app and form navigation.
- **Stuck signals (counts only, never keystroke contents).** Dwell, scroll reversals, re-reads, switching to search or AI tools, idle-but-present, time on task, typing rate, and error text.
- **Privacy flow.** The first call sends behavioural signals only. The window text is read (Accessibility first, else on-device Vision OCR, else a downscaled image to the local vision model) only after the service says you look stuck. The blocklist applies.
- **Learning.** Each guess is logged as picked, edited (the word diff is stored), typed-own or ignored. Past questions from the same mode and app are few-shot into the prompt, and a style summary is kept per mode. Sensitivity backs off on its own in modes where you keep ignoring it.
- **Dashboard → Companion** (key `C`):
  - hit rate ("Clicky guessed right N% this week");
  - per-day, per-mode and per-app accuracy;
  - history with diffs;
  - study sessions and learned styles;
  - settings: sensitivity, answer style, study detection, OCR, vision model.
- **API.** `POST /api/anticipate` (two-phase), `POST /api/answer` (NDJSON stream: start/delta/anchor/done), `POST /api/companion/feedback`, `GET /api/companion`.
- **Permissions.** Accessibility (required), Screen Recording (optional OCR), Microphone + Speech Recognition (optional, on-device), Automation for browsers (URL-based mode detection). Requires macOS 14+.
- **Design mock.** `companion-mock.html` (`?v=orb|card&th=dark|light`).

## v6: Conservative self-improvement loop

Briefing tunes itself only when your own history clearly shows a better setting. It never changes anything without your approval.

- **Telemetry (local only).** Events go to `~/Briefing/telemetry.jsonl`, rotated at 5 MB. It records:
  - companion outcomes;
  - model latency and failures (error types only);
  - API timings and exceptions;
  - automation approve/reject decisions;
  - next-move accept/dismiss with confidence;
  - briefing 👍/👎 from the Today card (or `briefing.py feedback up|down`).
  No content is ever logged. `briefing.py telemetry` prints the weekly metrics.
- **Nightly check.** `briefing.py improve` runs from a LaunchAgent at 02:30. It skips itself on battery power, when disk space is low, or while another run is in progress. Each run:
  - computes metrics and picks the top 1–2 problems (for example "companion ignored 40%" or "next-move dismissed 60%");
  - tries candidates cheapest first:
    - **Settings:** stuck threshold base, ignore back-off, companion cooldown, next-move confidence bar. Values come from a grid search replayed offline on your logged history. The search uses the oldest 70% of events, and the result is judged on the newest 30%, which the search never saw. Hard bounds always apply.
    - **Prompt wording:** variants of the companion prediction prompt, including one rewritten by the local model from the training split. They are replayed against held-out past moments where you typed or edited your question.
    - **Optional small code patch:** from `improve_code_model` (for example `qwen2.5-coder:14b`; off by default).
- **Code patch limits:**
  - only files in `improve_code_allowlist`;
  - at most `improve_max_diff_lines` changed lines;
  - no forbidden calls (subprocess, file I/O, network, eval);
  - never inside protected functions: blocklist/privacy, the approval and run paths for automations and resume, forget/cleanup, the HTTP origin checks, telemetry, Things/Obsidian sync, and the loop itself.
  - `improve.py`, `tests/`, `install.sh`, `uninstall.sh` and `Companion.swift` can never be patched.
- **Gate.** The app folder (`~/Briefing/app`) is a git repo. Each candidate is committed to its own `improve/<id>` branch in a temporary worktree. It must:
  - pass the **full test suite** (run against a scratch home, never your memory);
  - beat the baseline on held-out replay by more than `max(improve_min_gain, 2 × standard error)`;
  - have at least `improve_min_samples` cases;
  - lose no more than 5% of useful guesses;
  - for prompts: be no slower (≤ 1.25×) and produce no extra unparseable replies.
  A candidate that fails any check is discarded and the run is logged as "no change needed".
- **Your decision.** A winning candidate becomes a proposal. It appears in the morning briefing and in the dashboard's **Improvements** tab (key `I`), with metric deltas, a plain-English summary and the exact diff.
  - **Approve** saves a backup git bundle to `~/Briefing/improve/backups`, merges the branch and restarts the dashboard agent.
  - **Reject** deletes the branch.
  - **Undo** reverts any past approved merge.
  - CLI equivalents: `briefing.py proposals` and `briefing.py improve-decide <id> approve|reject|undo`.
  - `improve_auto_apply_params` (off by default) applies only setting-only winners automatically. Prompts and code always wait for you.
- **Where tuned values live.** `tunables.json` and `prompts.json` in the app folder. Any value you set yourself in `config.json` always wins over them. Re-installing keeps both files. An approved code patch is overwritten by a re-install (it stays in git history).

## Obsidian

`~/Briefing/memory` is a valid Obsidian vault. Open the folder as a vault and Graph view works. There's a minimal `.obsidian/` config, which ignores `.backups/` and `data/` and colour-codes the graph groups.
- Daily notes carry `tags: [daily]` front-matter and a **Links** footer with `[[project]]` and `[[Person]]` wikilinks.
- Project pages link each active day as `[[YYYY-MM-DD]]`.
- `people/<Name>.md` notes are generated from `people.md`, with a "Mentioned in" backlink list. Anything you write above the auto block is kept.
- Curated files get tags.
- Everything stays plain markdown.
- `briefing.py vault` runs the sync now (nightly runs it too). Disable it with `obsidian_links: false`.

## Things 3 (optional, off by default)

Set `things_sync: true` (Settings → Obsidian & Things); optionally set `things_list` to a project or area.
- **Adding:** new open loops and auto to-dos are sent with `open -g "things:///add?..."` and tagged `Briefing`. Each carries `briefing-id:<id>` in its notes for dedupe; sent ids are tracked in `memory/data/things.json`. Blocklisted items are never sent.
- **Completing:** when you close a loop here, Briefing completes it in Things through AppleScript, matching on that `briefing-id`. This needs no token, but macOS asks once for Automation permission.
- **`things:///update` route:** `things_auth_token` (Things → Settings → General → Enable Things URLs → Manage) is used only when a Things item id is known. Set it in `config.json`; it isn't shown in the dashboard.
- `briefing.py things-sync` forces a sync.

## Health check: `briefing.py doctor`

`python3 ~/Briefing/app/briefing.py doctor` (or Settings → Health in the dashboard) shows every job with state
(OK / late / error / never), last run time and last error: recorder link (newest Dayflow card), distill, nightly,
companion (orb check-ins), improve loop, cleanup, wake briefing, dashboard, plus Ollama + model, file permissions and git.
Results live in `~/Briefing/status.json`; `doctor --json` prints machine-readable output.

## Security & privacy

* Dashboard binds `127.0.0.1` only. Every request must carry a `Host` of `127.0.0.1:<port>`/`localhost:<port>` (blocks
  DNS rebinding); mutating requests must be `application/json` with no foreign `Origin` / cross-site `Sec-Fetch-Site`
  (blocks CSRF). Paths containing `..` are refused; memory writes resolve inside `~/Briefing/memory` or fail.
* `~/Briefing` is owner-only: umask 077 for every command, and `serve`/`nightly` re-tighten dirs to 0700 and files to 0600.
* `osascript`, `say`, `open` and Things calls use argv lists (never a shell); AppleScript strings are escaped, `say` gets
  `--` before text, Things URLs are percent-encoded. Tests: `tests/test_hardening.py`.
