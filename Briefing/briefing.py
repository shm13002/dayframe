#!/usr/bin/env python3
"""Dayflow Briefing add-on: local, keyless "where you left off" briefings.

Commands:
  briefing.py wake            # on login/wake: briefing (cooldown) + session-goal prompt
  briefing.py checkin         # periodic check-in prompt
  briefing.py distill         # pull new Dayflow cards + check-ins into ~/Briefing/memory/ (every 45 min)
  briefing.py nightly         # distill + weekly rollup + recordings cleanup
  briefing.py ask "question"  # answer from your memory folder (local search + Ollama)
  briefing.py cleanup         # delete distilled Dayflow recordings (dry-run unless enabled)
  briefing.py reindex         # rebuild the search index
  briefing.py brief --force   # show a briefing now
  briefing.py status          # health check
  briefing.py debrief         # end-of-day voice debrief (6pm)
  briefing.py coach           # distraction check (runs after each distill)
  briefing.py report          # weekly "you" report (Sunday)
  briefing.py forget --from 2026-10-01 --to 2026-10-03 [--rebuild]
  briefing.py context         # short "right now" context for LocalClicky-style tools
  briefing.py serve           # local dashboard + API on http://127.0.0.1:8765
Stdlib only. Talks to Ollama at localhost:11434 and reads Dayflow's DB read-only.
"""
import argparse, datetime as dt, hashlib, math, re, secrets, http.server, socketserver, json, os, platform, sqlite3, subprocess, sys, time, urllib.request, urllib.error, urllib.parse
from pathlib import Path

HOME = Path(os.environ.get("BRIEFING_HOME", Path.home() / "Briefing"))
CONFIG_PATH = HOME / "config.json"
MEM = HOME / "memory"
INBOX = MEM / "inbox.jsonl"
INDEX_DB = MEM / "index.sqlite"
LOG_DIR = HOME / "log"
STATE_PATH = HOME / "state.json"
ERR_LOG = HOME / "briefing.log"
DEFAULT_DB = Path.home() / "Library/Application Support/Dayflow/chunks.sqlite"

# RAM tier -> default text model (Ollama tags verified on ollama.com, Oct 2026).
# Leaves headroom for Dayflow's own vision model running at the same time.
RAM_TIERS = [  # (max_gb, model)
    (8, "qwen3.5:4b"),
    (16, "qwen3.5:9b"),
    (24, "gemma4:12b"),
    (32, "gemma4:26b"),
    (64, "qwen3.6:35b"),
    (10**6, "gpt-oss:120b"),
]

DEFAULTS = {
    "model": None,  # filled from RAM tier
    "ollama_url": "http://localhost:11434",
    "llm_backend": "ollama",         # ollama | openai (LM Studio) | claude_cli | codex_cli (your Claude / ChatGPT plan, no API key)
    "cli_model": "",                 # optional model for claude_cli / codex_cli; blank = the CLI's default
    "llm_url": "http://localhost:1234/v1",
    "cooldown_minutes": 30,
    "lookback_hours": 12,
    "speak": False,
    "voice": "",
    "ask_session_goal": True,
    "checkin_quiet_hours": [22, 8],  # no check-ins from 22:00 to 08:00
    "memory_max_chars": 6000,       # cap per curated file
    "daily_max_chars": 200000,
    "cleanup_enabled": False,        # False = dry-run report only
    "cleanup_min_age_hours": 24,
    "distill_batch_max_cards": 80,
    "blocklist": {"apps": [], "sites": [], "keywords": []},   # privacy guard: matching activity is never stored
    "debrief_hour": 18,
    "debrief_use_whisper": False,    # record 60s with ffmpeg + whisper.cpp if installed
    "coach_enabled": True,
    "coach_distraction_categories": ["Distraction", "Entertainment", "Social", "Social Media", "Leisure", "Personal"],
    "coach_threshold_minutes": 20,   # in the last 60 min
    "coach_cooldown_minutes": 90,
    "phone_push": "off",             # off | ntfy | imessage
    "ntfy_server": "https://ntfy.sh",
    "ntfy_topic": "",                # pick a long random topic; anyone who knows it can read it
    "imessage_to": "",               # your own phone number / Apple ID email
    "push_briefing": False,
    "meetily_db": "~/Library/Application Support/com.meetily.ai/meeting_minutes.sqlite",
    "dashboard_port": 8765,
    "nextmove_enabled": True,
    "nextmove_interval_minutes": 4,
    "nextmove_cooldown_minutes": 10,  # doubles with each consecutive dismiss (max x16)
    "nextmove_min_confidence": 0.55,
    "nextmove_focus_minutes": 25,     # don't interrupt after this much continuous focused work (except on app switch)
    "nextmove_idle_seconds": 300,
    "nextmove_speak": False,
    "companion_enabled": True,
    "companion_sensitivity": 0.6,     # 0 = only when very stuck, 1 = eager
    "companion_hint_mode": "auto",    # auto (hints when studying) | hints | direct
    "companion_study_detection": True,
    "companion_ocr": True,            # allow the screenshot+Vision OCR fallback when Accessibility text is empty
    "companion_cooldown_seconds": 240,
    "vision_model": "qwen2.5vl:7b",   # only used when no text could be read and a screenshot is sent
    "companion_study_apps": ["Preview", "Skim", "PDF Expert", "Notability", "GoodNotes", "Anki", "Kindle", "Books",
                             "MarginNote", "Zotero", "Obsidian", "Notion", "Overleaf"],
    "companion_study_sites": ["coursera.org", "khanacademy.org", "edx.org", "instructure.com", "canvas", "blackboard",
                              "brilliant.org", "chegg.com", "quizlet.com", "wolframalpha.com", "overleaf.com",
                              "gradescope.com", "piazza.com", "edstem.org", "libretexts.org", "ocw.mit.edu", "leetcode.com"],
    "embeddings": True,              # hybrid search: FTS5 + local embeddings
    "embed_model": "nomic-embed-text",
    "dayflow_db": str(DEFAULT_DB),
    "request_timeout_s": 180,
    # tunables the nightly self-improvement loop may propose changes to (via tunables.json in the app dir)
    "companion_threshold_base": 0.75,   # stuck threshold = base - 0.45 * sensitivity
    "companion_ignore_backoff": 0.12,   # added to the threshold in modes the user keeps ignoring
    "embed_min_similarity": 0.45,
    # self-improvement loop (never auto-applies code or prompts; see README)
    "improve_enabled": True,
    "improve_code_model": "",          # e.g. "qwen2.5-coder:14b"; empty = no code patches, only tuning
    "improve_code_allowlist": ["briefing.py"],   # protected functions inside are still off-limits
    "improve_max_diff_lines": 60,
    "improve_max_net_growth": 20,      # code patches may not grow the code by more than this (smallest diff wins)
    "improve_min_samples": 30,         # per metric, before any change is considered
    "improve_min_gain": 0.05,          # absolute improvement required (also must beat 2x standard error)
    "improve_min_prompt_cases": 12,
    "improve_auto_apply_params": False,  # True = param-only winners are applied without asking
    "improve_min_free_gb": 2,
    # Obsidian: memory/ is a vault (wikilinks + front-matter); Things 3 sync is opt-in
    "fact_review_days_changing": 7,     # 'changing' facts (status, deadlines, open loops) are re-checked this often
    "fact_review_days_stable": 120,     # habits, goals, preferences
    "fact_recheck_days": 7,             # how far back raw logs are searched when re-checking
    "obsidian_links": True,
    "things_sync": False,
    "things_auth_token": "",           # Things > Settings > General > Enable Things URLs > Manage; needed to mark done
    "things_list": "",                 # optional Things project/area name
}

APP_DIR = Path(__file__).resolve().parent
TELEMETRY_MAX_BYTES = 5_000_000

# ---------------------------------------------------------------- utils

def log(msg):
    HOME.mkdir(parents=True, exist_ok=True)
    with open(ERR_LOG, "a") as f:
        f.write(f"{dt.datetime.now().isoformat(timespec='seconds')} {msg}\n")

def ram_gb():
    try:
        out = subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True, text=True, timeout=5).stdout.strip()
        return int(out) / 1024**3
    except Exception:
        try:
            return os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES") / 1024**3
        except Exception:
            return 16.0

def model_for_ram(gb):
    for max_gb, model in RAM_TIERS:
        if gb <= max_gb + 0.5:
            return model
    return RAM_TIERS[-1][1]

def load_config():
    HOME.mkdir(parents=True, exist_ok=True)
    cfg = dict(DEFAULTS)
    if CONFIG_PATH.exists():
        try:
            cfg.update(json.loads(CONFIG_PATH.read_text()))
        except Exception as e:
            log(f"bad config.json, using defaults: {e}")
    user = {}
    if CONFIG_PATH.exists():
        try:
            user = json.loads(CONFIG_PATH.read_text())
        except Exception:
            pass
    for k, v in load_overrides("tunables.json").items():  # approved tuning; a value the user changed always wins
        if k in DEFAULTS and (k not in user or user[k] == DEFAULTS[k]):
            cfg[k] = v
    if not cfg.get("model"):
        cfg["model"] = model_for_ram(ram_gb())
    if not CONFIG_PATH.exists():
        CONFIG_PATH.write_text(json.dumps(cfg, indent=2))
    return cfg

def load_overrides(name):
    """tunables.json / prompts.json live in the app dir (git-tracked, so approve/undo is a merge/revert)."""
    if os.environ.get("BRIEFING_IGNORE_OVERRIDES") == "1":  # the test suite runs against plain defaults
        return {}
    try:
        d = json.loads((APP_DIR / name).read_text())
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}

def prompt_text(key, default):
    v = load_overrides("prompts.json").get(key)
    return v if isinstance(v, str) and v.strip() else default

def telemetry(kind, **kw):
    """Local-only metrics (no content): ~/Briefing/telemetry.jsonl, rotated at 5 MB."""
    try:
        p = HOME / "telemetry.jsonl"
        if p.exists() and p.stat().st_size > TELEMETRY_MAX_BYTES:
            p.replace(p.with_suffix(".jsonl.1"))
        with open(p, "a") as f:
            f.write(json.dumps(dict({"ts": round(time.time(), 3), "kind": kind}, **kw)) + "\n")
    except Exception:
        pass

def telemetry_read(since=0):
    out = []
    for p in (HOME / "telemetry.jsonl.1", HOME / "telemetry.jsonl"):
        if p.exists():
            for line in p.read_text().splitlines():
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                if e.get("ts", 0) >= since:
                    out.append(e)
    return out

def harden_perms(root=None):
    """Owner-only access for everything Briefing writes: dirs 0700, files 0600 (0700 if executable)."""
    os.umask(0o077)
    root = Path(root or HOME)
    if not root.exists():
        return 0
    n = 0
    for p in [root, *root.rglob("*")]:
        try:
            if p.is_symlink():
                continue
            m = p.stat().st_mode & 0o777
            want = 0o700 if p.is_dir() else (0o700 if m & 0o100 else 0o600)
            if m != want:
                os.chmod(p, want)
                n += 1
        except OSError:
            pass
    return n

def job_status(name, ok, detail="", error="", throttle=0):
    st = jload(HOME / "status.json", {})
    prev = st.get(name, {})
    if throttle and ok and prev.get("ok") and time.time() - (prev.get("last_run") or 0) < throttle:
        return
    st[name] = {"last_run": int(time.time()), "ok": bool(ok), "detail": str(detail)[:200], "error": str(error)[:300],
                "last_ok": int(time.time()) if ok else prev.get("last_ok")}
    jsave(HOME / "status.json", st)

JOBS = {  # name: (what it is, hours before "overdue")
    "recorder": ("Dayflow recording (newest card)", 2), "distill": ("Distill to memory (every 30 min)", 2),
    "nightly": ("Nightly memory upkeep", 30), "companion": ("Companion orb talking to the service", 1),
    "improve": ("Self-improvement check (02:30)", 30), "cleanup": ("Recording cleanup", 30),
    "wake": ("Wake briefing", 30), "dashboard": ("Dashboard server", 1e9)}

def doctor(cfg):
    """One look at what works: each job's last run, result and error, plus the local dependencies."""
    st = jload(HOME / "status.json", {})
    now = time.time()
    out = []
    con, err = open_dayflow(cfg)
    if con:
        try:
            r = con.execute("SELECT MAX(end_ts) FROM timeline_cards").fetchone()[0]
            st["recorder"] = {"last_run": r, "ok": bool(r) and now - r < 2 * 3600, "detail": "newest Dayflow card",
                              "error": "" if r and now - r < 2 * 3600 else "no new Dayflow cards for 2h+ (is Dayflow recording?)"}
        except Exception as e:
            st["recorder"] = {"last_run": None, "ok": False, "error": f"Dayflow read error: {e}"}
        finally:
            con.close()
    else:
        st["recorder"] = {"last_run": None, "ok": False, "error": err or "Dayflow database not found"}
    for name, (desc, hours) in JOBS.items():
        j = st.get(name)
        if not j:
            out.append({"job": name, "what": desc, "state": "never", "last_run": None, "error": "", "detail": ""})
            continue
        late = j.get("last_run") and now - j["last_run"] > hours * 3600
        state = "error" if not j.get("ok") else "late" if late else "ok"
        out.append({"job": name, "what": desc, "state": state, "last_run": j.get("last_run"), "last_ok": j.get("last_ok"),
                    "error": j.get("error", ""), "detail": j.get("detail", "")})
    what = f"Local model server ({llm_name(cfg)})"
    try:
        tags = llm_models(cfg)
        have = model_present(cfg, tags)
        deps = [{"job": "ollama", "what": what, "state": "ok" if have else "error", "last_run": int(now),
                 "error": "" if have else f"model {cfg['model']} not available ({missing_model_hint(cfg)})", "detail": f"{len(tags)} models"}]
    except Exception as e:
        deps = [{"job": "ollama", "what": what, "state": "error", "last_run": None, "error": f"not reachable at {llm_base(cfg)}: {e}", "detail": ""}]
    loose = [str(p.relative_to(HOME)) for p in [HOME, *HOME.rglob("*")] if not p.is_symlink() and p.exists() and p.stat().st_mode & 0o077][:5]
    deps.append({"job": "permissions", "what": "~/Briefing is owner-only", "state": "ok" if not loose else "error", "last_run": int(now),
                 "error": ("readable by others: " + ", ".join(loose)) if loose else "", "detail": ""})
    deps.append({"job": "git", "what": "App folder is a git repo (needed for improvements)", "state": "ok" if (APP_DIR / ".git").exists() else "error",
                 "last_run": int(now), "error": "" if (APP_DIR / ".git").exists() else "re-run install.sh", "detail": str(APP_DIR)})
    return {"checks": out + deps, "ok": all(c["state"] in ("ok", "never") for c in out + deps)}

def doctor_text(cfg):
    d = doctor(cfg)
    when = lambda t: dt.datetime.fromtimestamp(t).strftime("%a %H:%M") if t else "-"
    rows = [f"{'OK ' if c['state'] == 'ok' else c['state'].upper():6} {c['job']:<12} {when(c['last_run']):<10} {c['what']}" +
            (f"\n       ↳ {c['error']}" if c["error"] else "") for c in d["checks"]]
    return "\n".join(rows) + ("\n\nAll good." if d["ok"] else "\n\nSome checks need attention (see ↳ lines).")

def load_state():
    try:
        return json.loads(STATE_PATH.read_text())
    except Exception:
        return {}

def save_state(st):
    HOME.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(st, indent=2))

def today_log_path(day=None):
    day = day or dt.date.today()
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    return LOG_DIR / f"{day.isoformat()}.md"

def append_log(kind, text, day=None):
    p = today_log_path(day)
    new = not p.exists()
    with open(p, "a") as f:
        if new:
            f.write(f"# {(day or dt.date.today()).isoformat()}\n\n")
        f.write(f"- {dt.datetime.now().strftime('%H:%M')} **{kind}**: {text.strip()}\n")

def is_mac():
    return platform.system() == "Darwin"

def osa_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')

# ---------------------------------------------------------------- UI (macOS; prints elsewhere)

def ask(prompt, title="Briefing", default=""):
    """Text-input dialog. Returns '' if cancelled or not on macOS (unless BRIEFING_TEST_ANSWER set)."""
    if "BRIEFING_TEST_ANSWER" in os.environ:
        return os.environ["BRIEFING_TEST_ANSWER"]
    if not is_mac():
        print(f"[ask] {prompt}")
        return ""
    script = (f'set r to display dialog "{osa_escape(prompt)}" default answer "{osa_escape(default)}" '
              f'with title "{osa_escape(title)}" buttons {{"Skip", "Save"}} default button "Save" giving up after 600\n'
              f'if button returned of r is "Save" then return text returned of r')
    try:
        r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=660)
        return r.stdout.strip()
    except Exception as e:
        log(f"ask failed: {e}")
        return ""

def show(text, title="Where you left off"):
    if not is_mac():
        print(f"===== {title} =====\n{text}\n")
        return
    short = text if len(text) < 1800 else text[:1800] + "…"
    script = (f'display dialog "{osa_escape(short)}" with title "{osa_escape(title)}" '
              f'buttons {{"OK"}} default button "OK" giving up after 900')
    try:
        subprocess.run(["osascript", "-e", script], capture_output=True, timeout=960)
    except Exception as e:
        log(f"show failed: {e}")

def notify(text, title="Briefing"):
    if is_mac():
        subprocess.run(["osascript", "-e", f'display notification "{osa_escape(text[:200])}" with title "{osa_escape(title)}"'],
                       capture_output=True)
    else:
        print(f"[notify] {title}: {text}")

def speak(text, cfg):
    if not cfg.get("speak") or not is_mac():
        return
    args = ["say"] + (["-v", str(cfg["voice"])] if cfg.get("voice") else []) + ["--", text[:1500]]  # "--": text is never an option
    try:
        subprocess.Popen(args)
    except Exception as e:
        log(f"say failed: {e}")

# ---------------------------------------------------------------- Dayflow (read-only)

REQUIRED = {
    "timeline_cards": {"start_ts", "end_ts", "day", "title", "summary", "category"},
}
OPTIONAL = {
    "journal_entries": {"day", "intentions", "goals", "reflections", "summary"},
    "screenshots": {"id", "captured_at", "file_path"},
    "batch_screenshots": {"batch_id", "screenshot_id"},
    "analysis_batches": {"id", "status"},
    "chunks": {"id", "file_url", "status"},
    "batch_chunks": {"batch_id", "chunk_id"},
    "daily_standup_entries": {"standup_day", "payload_json"},
}

JOB_ERRORS = []  # real failures during the current CLI job (LLM / data source); decides job status + exit code

def job_error(msg):
    if len(JOB_ERRORS) < 20:
        JOB_ERRORS.append(msg)
    return msg

def open_dayflow(cfg):
    p = Path(os.path.expanduser(cfg["dayflow_db"]))
    if not p.exists():
        return None, job_error(f"Dayflow database not found at {p} (is Dayflow installed and has it recorded once?)")
    try:
        con = sqlite3.connect(f"file:{p}?mode=ro", uri=True, timeout=5)
        con.row_factory = sqlite3.Row
        return con, None
    except Exception as e:
        return None, job_error(f"cannot open Dayflow DB read-only: {e}")

def table_cols(con, table):
    try:
        return {r[1] for r in con.execute(f"PRAGMA table_info({table})")}
    except Exception:
        return set()

def check_schema(con):
    ok, problems = {}, []
    for t, cols in {**REQUIRED, **OPTIONAL}.items():
        have = table_cols(con, t)
        missing = cols - have
        ok[t] = not missing
        if missing and t in REQUIRED:
            problems.append(f"{t} missing columns {sorted(missing)}")
    return ok, problems

def fetch_activity(cfg, since_ts=None, day=None):
    """Return (cards, journal, standup, note). Never raises."""
    con, err = open_dayflow(cfg)
    if not con:
        return [], None, None, err
    try:
        ok, problems = check_schema(con)
        if problems:
            return [], None, None, job_error("Dayflow schema changed: " + "; ".join(problems))
        if day:
            rows = con.execute("SELECT start_ts,end_ts,title,summary,category,day FROM timeline_cards "
                               "WHERE day=? ORDER BY start_ts", (day,)).fetchall()
        else:
            rows = con.execute("SELECT start_ts,end_ts,title,summary,category,day FROM timeline_cards "
                               "WHERE start_ts>=? ORDER BY start_ts", (int(since_ts or 0),)).fetchall()
        cards = [dict(r) for r in rows]
        journal = standup = None
        if ok.get("journal_entries"):
            r = con.execute("SELECT day,intentions,goals,reflections,summary FROM journal_entries "
                            "ORDER BY day DESC LIMIT 1").fetchone()
            journal = dict(r) if r else None
        if ok.get("daily_standup_entries"):
            r = con.execute("SELECT standup_day,payload_json FROM daily_standup_entries "
                            "ORDER BY standup_day DESC LIMIT 1").fetchone()
            standup = dict(r) if r else None
        return cards, journal, standup, None
    except Exception as e:
        return [], None, None, f"Dayflow read error: {e}"
    finally:
        con.close()

def fmt_cards(cards, limit=60):
    out = []
    for c in cards[-limit:]:
        try:
            t0 = dt.datetime.fromtimestamp(c["start_ts"]).strftime("%H:%M")
            t1 = dt.datetime.fromtimestamp(c["end_ts"]).strftime("%H:%M")
        except Exception:
            t0 = t1 = "?"
        out.append(f"- {t0}-{t1} [{c.get('category','')}] {c.get('title','')}: {(c.get('summary') or '')[:300]}")
    return "\n".join(out)

# ---------------------------------------------------------------- LLM backends (Ollama, or OpenAI-compatible e.g. LM Studio)

def is_openai(cfg):
    return cfg.get("llm_backend") == "openai"

def is_cli(cfg):
    return cfg.get("llm_backend") in ("claude_cli", "codex_cli")

def llm_name(cfg):
    return {"openai": "LM Studio", "claude_cli": "Claude (your plan)", "codex_cli": "ChatGPT (your plan)"}.get(
        cfg.get("llm_backend"), "Ollama")

CLI_DIRS = [str(Path.home() / ".local/bin"), "/opt/homebrew/bin", "/usr/local/bin", str(Path.home() / ".npm-global/bin")]

def cli_bin(cfg):
    import shutil
    name = "claude" if cfg.get("llm_backend") == "claude_cli" else "codex"
    return shutil.which(name, path=os.pathsep.join(CLI_DIRS + [os.environ.get("PATH", "")]))

def cli_chat(cfg, system, user):
    """Run one prompt through the Claude Code or Codex CLI, signed in with the user's own plan.
    Returns (text, error). Tools, MCP servers and web search are off: it only writes text."""
    exe = cli_bin(cfg)
    backend = cfg.get("llm_backend")
    if not exe:
        return "", f"{'claude' if backend == 'claude_cli' else 'codex'} CLI not found (install it and sign in)"
    model = (cfg.get("cli_model") or "").strip()
    sandbox = HOME / ".cli-sandbox"   # empty working dir so no project context leaks in
    sandbox.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, PATH=os.pathsep.join(CLI_DIRS + [os.environ.get("PATH", "/usr/bin:/bin")]))
    if backend == "claude_cli":
        cmd = [exe, "-p", "--output-format", "json", "--allowedTools", "[]", "--strict-mcp-config",
               "--append-system-prompt", system]
        if model:
            cmd += ["--model", model]
        stdin = user
    else:
        cmd = [exe, "exec", "--skip-git-repo-check", "--json", "-c", "web_search=disabled", "-c", "rmcp_client=false"]
        if model:
            cmd += ["-m", model]
        cmd += ["-"]
        stdin = f"{system}\n\n---\n\n{user}"
    t0 = time.time()
    try:
        r = subprocess.run(cmd, input=stdin, capture_output=True, text=True, cwd=sandbox, env=env,
                           timeout=max(120, cfg.get("request_timeout_s", 180) * 2))
    except subprocess.TimeoutExpired:
        telemetry("llm", ms=int((time.time() - t0) * 1000), ok=False, backend=backend, error="timeout")
        return "", f"{llm_name(cfg)} timed out"
    ms = int((time.time() - t0) * 1000)
    text, tin, tout, cli_err = "", 0, 0, ""
    if backend == "claude_cli":
        try:
            j = json.loads(r.stdout.strip().splitlines()[-1])
            text = j.get("result") or ""
            u = j.get("usage") or {}
            tin = int(u.get("input_tokens", 0)) + int(u.get("cache_read_input_tokens", 0)) + int(u.get("cache_creation_input_tokens", 0))
            tout = int(u.get("output_tokens", 0))
            if j.get("is_error"):
                text, cli_err = "", str(j.get("result") or "error")
        except Exception:
            text = ""
    else:
        for line in r.stdout.splitlines():
            try:
                ev = json.loads(line)
            except Exception:
                continue
            item = ev.get("item") or {}
            if ev.get("type") == "item.completed" and item.get("type") in ("agent_message", "assistant_message"):
                text = item.get("text") or text
            u = ev.get("usage") or {}
            if u:
                tin, tout = int(u.get("input_tokens", tin)), int(u.get("output_tokens", tout))
    ok = bool(text.strip()) and r.returncode == 0
    telemetry("llm", ms=ms, ok=ok, backend=backend, tokens_in=tin, tokens_out=tout)
    if not ok:
        err = cli_err or ((r.stderr or r.stdout or "").strip().splitlines()[-1:] or ["no output"])[0]
        if "authenticat" in err.lower() or "login" in err.lower():
            err += " (sign in: run `claude` then /login)" if backend == "claude_cli" else " (sign in: run `codex login`)"
        return "", f"{llm_name(cfg)} failed: {err[:240]}"
    return strip_think(text), None

def llm_base(cfg):
    return (cfg["llm_url"] if is_openai(cfg) else cfg["ollama_url"]).rstrip("/")

def strip_think(s):
    return re.sub(r"(?s)<think>.*?</think>", "", s or "").strip()

def openai_messages(system, user, images=None):
    content = user
    if images:  # base64 PNG/JPEG → OpenAI image parts
        content = [{"type": "text", "text": user}] + [
            {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + im}} for im in images]
    return [{"role": "system", "content": system}, {"role": "user", "content": content}]

def llm_models(cfg):
    """Model ids the server has (raises if unreachable)."""
    if is_cli(cfg):
        exe = cli_bin(cfg)
        if not exe:
            raise RuntimeError("CLI not installed")
        return {cfg["model"], "cli"}
    if is_openai(cfg):
        with urllib.request.urlopen(llm_base(cfg) + "/models", timeout=5) as r:
            return {m.get("id", "") for m in json.loads(r.read()).get("data", [])}
    with urllib.request.urlopen(llm_base(cfg) + "/api/tags", timeout=5) as r:
        return {m.get("name", "") for m in json.loads(r.read()).get("models", [])}

def model_present(cfg, models):
    m = cfg["model"]
    return m in models or any(t.split(":")[0] == m.split(":")[0] for t in models)

def missing_model_hint(cfg, model=None):
    m = model or cfg["model"]
    return f"lms load {m}" if is_openai(cfg) else f"ollama pull {m}"

def ollama_chat(cfg, system, user, images=None, model=None):
    if is_cli(cfg) and not images:  # screenshots for the orb stay with the local vision model
        out, err = cli_chat(cfg, system, user)
        if not err:
            return out, None
        log(f"{err}; falling back to local Ollama")
        cfg = dict(cfg, llm_backend="ollama")
    if is_openai(cfg):
        return openai_chat(cfg, system, user, images, model)
    url = cfg["ollama_url"].rstrip("/") + "/api/chat"
    um = {"role": "user", "content": user}
    if images:
        um["images"] = images  # base64 PNG/JPEG, for vision models
    body = json.dumps({"model": model or cfg["model"], "stream": False, "think": False,
                       "options": {"temperature": 0.3},
                       "messages": [{"role": "system", "content": system}, um]}).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=cfg["request_timeout_s"]) as r:
            data = json.loads(r.read())
        telemetry("llm", ms=int((time.time() - t0) * 1000), ok=True, vision=bool(images))
        return (data.get("message") or {}).get("content", "").strip(), None
    except urllib.error.URLError as e:
        telemetry("llm", ms=int((time.time() - t0) * 1000), ok=False, error="unreachable")
        return "", job_error(f"Ollama not reachable at {cfg['ollama_url']} ({e}). Is the Ollama app running?")
    except Exception as e:
        telemetry("llm", ms=int((time.time() - t0) * 1000), ok=False, error=type(e).__name__)
        return "", job_error(f"Ollama error: {e} (model pulled? `ollama pull {model or cfg['model']}`)")

def openai_chat(cfg, system, user, images=None, model=None):
    body = json.dumps({"model": model or cfg["model"], "stream": False, "temperature": 0.3,
                       "messages": openai_messages(system, user, images)}).encode()
    req = urllib.request.Request(llm_base(cfg) + "/chat/completions", data=body, headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=cfg["request_timeout_s"]) as r:
            data = json.loads(r.read())
        telemetry("llm", ms=int((time.time() - t0) * 1000), ok=True, vision=bool(images))
        msg = ((data.get("choices") or [{}])[0].get("message") or {})
        return strip_think(msg.get("content", "")), None
    except urllib.error.HTTPError as e:
        telemetry("llm", ms=int((time.time() - t0) * 1000), ok=False, error=f"http{e.code}")
        return "", job_error(f"LM Studio error {e.code}: {e.read()[:200]!r} (model loaded? `{missing_model_hint(cfg, model)}`)")
    except urllib.error.URLError as e:
        telemetry("llm", ms=int((time.time() - t0) * 1000), ok=False, error="unreachable")
        return "", job_error(f"LM Studio not reachable at {llm_base(cfg)} ({e}). Is its server on? (`lms server start`)")
    except Exception as e:
        telemetry("llm", ms=int((time.time() - t0) * 1000), ok=False, error=type(e).__name__)
        return "", job_error(f"LM Studio error: {e}")

def read(p, n=None):
    try:
        s = Path(p).read_text()
        return s[-n:] if n else s
    except Exception:
        return ""

# ---------------------------------------------------------------- memory folder helpers

CURATED = ["profile.md", "goals.md", "open-loops.md", "people.md", "patterns.md"]
CURATED_DESC = {
    "profile.md": "who the user is: role, skills, tools they use, preferences, work style",
    "goals.md": "current goals (short and long term) with status",
    "open-loops.md": "unfinished tasks, promises, things waiting on others; remove or mark done when resolved",
    "people.md": "people the user interacts with: name, relation, context, last interaction",
    "patterns.md": "habits, focus times, typical schedule, distractions, productivity patterns",
}

def mem_init():
    for d in (MEM, MEM / "daily", MEM / "projects", MEM / "weekly", MEM / ".backups"):
        d.mkdir(parents=True, exist_ok=True)
    for f in CURATED:
        p = MEM / f
        if not p.exists():
            p.write_text(f"# {f[:-3].replace('-', ' ').title()}\n\n_{CURATED_DESC[f]}_\n")

def slugify(name):
    s = "".join(c.lower() if c.isalnum() else "-" for c in name).strip("-")
    while "--" in s:
        s = s.replace("--", "-")
    return s[:60] or "misc"

def backup(p, keep=5):
    if not p.exists():
        return
    bdir = MEM / ".backups"
    bdir.mkdir(parents=True, exist_ok=True)
    rel = str(p.relative_to(MEM)).replace("/", "__")
    (bdir / f"{rel}.{int(time.time()*1000)}").write_text(p.read_text())
    olds = sorted(bdir.glob(f"{rel}.*"), key=lambda x: x.name)
    for o in olds[:-keep]:
        o.unlink()

def safe_write(p, text, cap):
    """Write an LLM-updated file with backup and size cap; refuse suspicious shrinkage."""
    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`").split("\n", 1)[-1].rstrip("`").strip()
    old = p.read_text() if p.exists() else ""
    if len(text) < 30:
        log(f"refused empty update to {p.name}")
        return False
    if old and len(old) > 400 and len(text) < 0.3 * len(old):
        log(f"refused update to {p.name}: shrank {len(old)}->{len(text)} chars")
        return False
    backup(p)
    if len(text) > cap:
        text = text[:cap].rsplit("\n", 1)[0] + "\n\n_(trimmed to size cap)_"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text + "\n")
    return True

def inbox_add(kind, text):
    MEM.mkdir(parents=True, exist_ok=True)
    with open(INBOX, "a") as f:
        f.write(json.dumps({"ts": time.time(), "kind": kind, "text": text}) + "\n")

def inbox_since(ts):
    out = []
    try:
        for line in INBOX.read_text().splitlines():
            try:
                e = json.loads(line)
                if e.get("ts", 0) > ts:
                    out.append(e)
            except Exception:
                pass
    except FileNotFoundError:
        pass
    return out

# ---------------------------------------------------------------- daily detailed logs

def fetch_new_cards(cfg, after_id, limit):
    con, err = open_dayflow(cfg)
    if not con:
        return [], err
    try:
        ok, problems = check_schema(con)
        if problems:
            return [], "Dayflow schema changed: " + "; ".join(problems)
        cols = table_cols(con, "timeline_cards")
        want = [c for c in ("id", "batch_id", "start_ts", "end_ts", "day", "title", "summary", "category",
                            "subcategory", "detailed_summary", "metadata") if c in cols]
        where = "id > ?" + (" AND is_deleted = 0" if "is_deleted" in cols else "")
        rows = con.execute(f"SELECT {','.join(want)} FROM timeline_cards WHERE {where} ORDER BY id LIMIT ?",
                           (after_id, limit)).fetchall()
        return [dict(r) for r in rows], None
    except Exception as e:
        return [], f"Dayflow read error: {e}"
    finally:
        con.close()

def hm(ts):
    try:
        return dt.datetime.fromtimestamp(int(ts)).strftime("%H:%M")
    except Exception:
        return "?"



# ---------------------------------------------------------------- LLM curation



def parse_json(text):
    text = text.strip()
    if "```" in text:
        text = text.split("```")[1].lstrip("json").strip() if text.count("```") >= 2 else text
    a, b = text.find("{"), text.rfind("}")
    if a < 0 or b < 0:
        return None
    try:
        return json.loads(text[a:b + 1])
    except Exception:
        return None

def merge_file(cfg, path, desc, facts, cap=None):
    cap = cap or cfg["memory_max_chars"]
    existing = path.read_text() if path.exists() else f"# {path.stem}\n"
    user = f"EXISTING FILE:\n{existing}\n\nNEW FACTS ({dt.date.today()}):\n" + "\n".join(f"- {f}" for f in facts)
    out, err = ollama_chat(cfg, MERGE_SYS.format(desc=desc, cap=cap), user)
    if err:
        log(f"merge {path.name}: {err}")
        return False
    return safe_write(path, out, cap)


# ---------------------------------------------------------------- distill / weekly


def cmd_weekly(cfg, day=None):
    day = day or dt.date.today()
    y, w, _ = day.isocalendar()
    monday = day - dt.timedelta(days=day.weekday())
    texts = []
    for i in range(7):
        p = MEM / "daily" / f"{(monday + dt.timedelta(days=i)).isoformat()}.md"
        if p.exists():
            texts.append(p.read_text()[-8000:])
    if not texts:
        return "no daily files"
    p = MEM / "weekly" / f"{y}-W{w:02d}.md"
    sys_p = ("Write a weekly rollup in Markdown from these daily logs: ## Summary, ## By project, "
             "## Wins, ## Open loops, ## Focus & patterns. Be specific and factual. Under 5000 characters.")
    out, err = ollama_chat(cfg, sys_p, "\n\n".join(texts)[:30000])
    if err:
        return f"weekly failed: {err}"
    safe_write(p, out, 6000)
    return f"weekly {p.name}"

# ---------------------------------------------------------------- search index (SQLite FTS5)

def _chunks(text, size=900):
    paras, buf = text.split("\n\n"), ""
    for para in paras:
        if len(buf) + len(para) > size and buf:
            yield buf
            buf = ""
        buf += para + "\n\n"
    if buf.strip():
        yield buf



def dates_in(question):
    import re
    out = set(re.findall(r"\d{4}-\d{2}-\d{2}", question))
    ql = question.lower()
    today = dt.date.today()
    if "yesterday" in ql:
        out.add((today - dt.timedelta(days=1)).isoformat())
    if "today" in ql:
        out.add(today.isoformat())
    for i, name in enumerate(["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]):
        if name in ql:
            delta = (today.weekday() - i) % 7 or 7
            out.add((today - dt.timedelta(days=delta)).isoformat())
    return sorted(out)


# ---------------------------------------------------------------- recordings cleanup

def deletable_recordings(cfg):
    """Return (candidates[(path,bytes,reason)], skipped_count, note). Read-only DB access.
    A file is deletable only if: it is inside Dayflow's recordings dir, is a regular non-DB file,
    older than cleanup_min_age_hours, referenced by Dayflow, every reference belongs to a 'completed'
    analysis batch, and every one of those batches has timeline cards already distilled (id <= watermark)."""
    dbp = Path(os.path.expanduser(cfg["dayflow_db"]))
    root = (dbp.parent / "recordings").resolve()
    if not root.is_dir():
        return [], 0, f"no recordings dir at {root}"
    wm = load_state().get("wm_card_id", 0)
    con, err = open_dayflow(cfg)
    if not con:
        return [], 0, err
    refs = {}  # resolved path -> list of batch ids (None = not in any batch)
    try:
        def add_refs(sql):
            for path, bid in con.execute(sql):
                if not path:
                    continue
                if path.startswith("file://"):
                    path = urllib.request.url2pathname(path[7:])
                try:
                    rp = str(Path(path).resolve())
                except Exception:
                    continue
                refs.setdefault(rp, []).append(bid)
        tabs = {t: table_cols(con, t) for t in ("screenshots", "batch_screenshots", "chunks", "batch_chunks")}
        if {"id", "file_path"} <= tabs["screenshots"] and {"batch_id", "screenshot_id"} <= tabs["batch_screenshots"]:
            add_refs("SELECT s.file_path, bs.batch_id FROM screenshots s "
                     "LEFT JOIN batch_screenshots bs ON bs.screenshot_id = s.id")
        if {"id", "file_url"} <= tabs["chunks"] and {"batch_id", "chunk_id"} <= tabs["batch_chunks"]:
            add_refs("SELECT c.file_url, bc.batch_id FROM chunks c LEFT JOIN batch_chunks bc ON bc.chunk_id = c.id")
        batch_ok = {}
        if {"id", "status"} <= table_cols(con, "analysis_batches"):
            for bid, status in con.execute("SELECT id, status FROM analysis_batches"):
                batch_ok[bid] = status == "completed"
        distilled = {}
        for bid, mx in con.execute("SELECT batch_id, MAX(id) FROM timeline_cards GROUP BY batch_id"):
            distilled[bid] = mx is not None and mx <= wm
    except Exception as e:
        return [], 0, f"cleanup read error: {e}"
    finally:
        con.close()
    cutoff = time.time() - cfg["cleanup_min_age_hours"] * 3600
    cands, skipped = [], 0
    for p in root.rglob("*"):
        try:
            if p.is_symlink() or not p.is_file():
                continue
            rp = p.resolve()
            if root not in rp.parents:
                continue
            name = p.name.lower()
            if ".sqlite" in name or name.endswith((".db", "-wal", "-shm", ".json", ".plist")):
                continue
            if p.stat().st_mtime > cutoff:
                skipped += 1
                continue
            bids = refs.get(str(rp))
            if not bids:
                skipped += 1  # unknown to Dayflow: leave it (Dayflow cleans its own stragglers)
                continue
            if all(b is not None and batch_ok.get(b) and distilled.get(b) for b in bids):
                cands.append((rp, p.stat().st_size, f"{len(bids)} refs, batches {sorted(set(bids))[:5]}"))
            else:
                skipped += 1
        except Exception:
            skipped += 1
    return cands, skipped, None

def cmd_cleanup(cfg):
    cands, skipped, note = deletable_recordings(cfg)
    if note:
        log(note)
        return note
    total = sum(b for _, b, _ in cands)
    live = bool(cfg.get("cleanup_enabled"))
    lines = [f"# Recordings cleanup {dt.datetime.now():%Y-%m-%d %H:%M} ({'DELETED' if live else 'DRY RUN'})",
             f"{len(cands)} files, {total/1e6:.1f} MB eligible; {skipped} kept (too new, unprocessed, or unknown)."]
    deleted = 0
    for p, b, why in cands:
        lines.append(f"- {p} ({b/1e6:.1f} MB; {why})")
        if live:
            try:
                p.unlink()
                deleted += 1
            except Exception as e:
                lines.append(f"  - failed: {e}")
    MEM.mkdir(parents=True, exist_ok=True)
    (MEM / "cleanup-report.md").write_text("\n".join(lines[:500]) + "\n")
    return f"{'deleted' if live else 'dry-run'}: {deleted if live else len(cands)} files, {total/1e6:.1f} MB"

# ---------------------------------------------------------------- briefing

BRIEF_SYS = ("You are a concise personal work assistant. Using the user's memory files (profile, goals, open loops, "
             "projects), the latest daily log, and recent screen activity, write a short briefing with exactly three sections:\n"
             "WHERE YOU LEFT OFF: 2-3 sentences, concrete (files, sites, tasks).\n"
             "YOUR GOAL: the current goal from their notes/memory; say 'not set' if unknown.\n"
             "NEXT STEPS: 3 numbered, specific actions (prefer open loops and project next steps).\n"
             "Handoff style: compact, like notes for a colleague taking over. Point to memory/project files by their path "
             "(e.g. memory/projects/x.md) instead of repeating their contents. Never repeat secrets, passwords, tokens, "
             "emails or phone numbers. Plain text, under 170 words, no preamble.")

# Redaction runs on everything shown, spoken, pushed or stored from a briefing (belt and braces after the prompt rule).
REDACT_RULES = [
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", re.S), "[private key]"),
    (re.compile(r"\b(?:sk|pk|rk)-(?:live-|test-|proj-)?[A-Za-z0-9_-]{16,}\b"), "[api key]"),
    (re.compile(r"\b(?:ghp|gho|ghs|github_pat|xox[abpors]|glpat)[-_][A-Za-z0-9_-]{16,}\b"), "[token]"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "[aws key]"),
    (re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"), "[jwt]"),
    (re.compile(r"(?i)\b(password|passwd|pwd|passcode|pin|secret|api[_ -]?key|token)\b(\s*(?:is|:|=)\s*)\S+"), r"\1\2[redacted]"),
    (re.compile(r"[\w.+-]+@[\w-]+\.[\w.]{2,}"), "[email]"),
    (re.compile(r"\b\d{3}-\d{2}-\d{4}\b"), "[ssn]"),
    (re.compile(r"\b(?:\d[ -]?){13,16}\b"), "[card]"),
    (re.compile(r"(?<![\w#])(?:\+?\d{1,3}[ .-]?)?\(?\d{3}\)?[ .-]\d{3}[ .-]\d{4}\b"), "[phone]"),
    (re.compile(r"\b[A-Fa-f0-9]{40,}\b"), "[secret]"),
]

def redact(text):
    t = str(text or "")
    for rx, rep_ in REDACT_RULES:
        t = rx.sub(rep_, t)
    return t

def relevant_projects(cards, n=3):
    projs = list((MEM / "projects").glob("*.md")) if (MEM / "projects").exists() else []
    if not projs:
        return []
    recent = " ".join(f"{c.get('title','')} {c.get('summary') or ''}" for c in cards[-15:]).lower()
    scored = []
    for p in projs:
        words = [w for w in p.stem.split("-") if len(w) > 2]
        score = sum(recent.count(w) for w in words)
        scored.append((score, p.stat().st_mtime, p))
    scored.sort(key=lambda x: (x[0], x[1]), reverse=True)
    return [p for _, _, p in scored[:n]]

def last_daily():
    files = sorted((MEM / "daily").glob("*.md")) if (MEM / "daily").exists() else []
    return files[-1] if files else None






def cmd_status(cfg):
    con, err = open_dayflow(cfg)
    db = err or "ok"
    if con:
        _, probs = check_schema(con); con.close()
        db = "ok" if not probs else "schema: " + "; ".join(probs)
    try:
        models = llm_models(cfg)
        ol = f"ok ({'model present' if model_present(cfg, models) else 'model NOT available: ' + missing_model_hint(cfg)})"
    except Exception as e:
        ol = f"unreachable ({e})"
    st = load_state()
    print(json.dumps({"ram_gb": round(ram_gb(), 1), "config": cfg, "dayflow_db": db, "ollama": ol, "llm_backend": llm_name(cfg),
                      "memory_dir": str(MEM), "watermark_card_id": st.get("wm_card_id", 0),
                      "cleanup": "ENABLED" if cfg.get("cleanup_enabled") else "dry-run"}, indent=2))

# ======================================================================= v3 features

TODOS = MEM / "todos.json"
DATA = MEM / "data"
URL_RE = re.compile(r"https?://[^\s)>\]\"']+")
PATH_RE = re.compile(r"(?:~|/Users/[^/\s]+)/[^\s:;,\"'()]+\.[A-Za-z0-9]{1,6}")
FILE_RE = re.compile(r"\b[\w\-]+\.(?:py|js|ts|tsx|swift|md|css|html|json|pdf|docx|xlsx|pptx|key|numbers|pages|fig|sketch|csv)\b")
TODO_RE = re.compile(r"(?:\bI (?:need|have|got) to|\bI should|\bremember to|\bTODO[: ]|\bdon'?t forget to|\bneed to)\s+([^.;\n!?{}\[\]]{4,140})"
                     r"|\b(follow up (?:with|on) [^.;\n!?{}\[\]]{3,140})", re.I)

# ---------------------------------------------------------------- push (phone)

def push(cfg, title, text):
    mode = cfg.get("phone_push", "off")
    try:
        if mode == "ntfy" and cfg.get("ntfy_topic"):
            req = urllib.request.Request(cfg["ntfy_server"].rstrip("/") + "/" + cfg["ntfy_topic"],
                                         data=text[:3500].encode(), headers={"Title": title[:200]})
            urllib.request.urlopen(req, timeout=10).read()
            return "ntfy"
        if mode == "imessage" and cfg.get("imessage_to") and is_mac():
            sc = ('tell application "Messages" to send "%s" to participant "%s" of (1st account whose service type = iMessage)'
                  % (osa_escape(title + "\n" + text[:3000]), osa_escape(cfg["imessage_to"])))
            subprocess.run(["osascript", "-e", sc], capture_output=True, timeout=30)
            return "imessage"
    except Exception as e:
        log(f"push failed: {e}")
    return "off"

# ---------------------------------------------------------------- privacy guard

def blocked(cfg, text):
    bl = cfg.get("blocklist") or {}
    t = (text or "").lower()
    for key in ("apps", "sites", "keywords"):
        for w in bl.get(key) or []:
            if w and w.lower() in t:
                return w
    return None

def card_text(c):
    return " ".join(str(c.get(k) or "") for k in ("title", "summary", "detailed_summary", "metadata", "category", "subcategory", "text"))

# ---------------------------------------------------------------- todos (open loops)

def todos_load():
    try:
        return json.loads(TODOS.read_text())
    except Exception:
        return []

def todos_save(items):
    _todos_save(items)
    try:
        cfg = load_config()
        if cfg.get("things_sync"):
            things_sync(cfg)
    except Exception as e:
        log(f"things sync failed: {e!r}")

def _todos_save(items):
    MEM.mkdir(parents=True, exist_ok=True)
    TODOS.write_text(json.dumps(items, indent=1))
    render_open_loops(items)

def norm(t):
    return re.sub(r"[^a-z0-9 ]", "", t.lower()).strip()

def todo_add(text, source, day=None, fact_id=None, sources=None):
    text = text.strip().rstrip(".")
    if len(text) < 4:
        return False
    items = todos_load()
    n = norm(text)
    stop = {"the", "a", "an", "to", "of", "for", "my", "on", "with", "and"}
    nw = set(n.split()) - stop
    for it in items:
        if it["done"]:
            continue
        w = set(norm(it["text"]).split()) - stop
        if norm(it["text"]) == n or (w and nw and len(w & nw) / min(len(w), len(nw)) >= 0.75):
            return False
    it = {"id": secrets.token_hex(4), "text": text, "source": source,
          "created": day or dt.date.today().isoformat(), "done": False, "done_at": None}
    if fact_id:
        it["fact_id"] = fact_id
    if sources:
        it["sources"] = list(sources)[:5]
    items.append(it)
    todos_save(items)
    return True

def todo_resolve(text):
    items, n, hit = todos_load(), norm(text), False
    words = set(n.split())
    for it in items:
        if it["done"]:
            continue
        w = set(norm(it["text"]).split())
        if w and len(words & w) / len(w) >= 0.6:
            it["done"], it["done_at"], hit = True, dt.date.today().isoformat(), True
    if hit:
        todos_save(items)
    return hit

def todo_set(tid, done):
    items = todos_load()
    for it in items:
        if it["id"] == tid:
            it["done"] = bool(done)
            it["done_at"] = dt.date.today().isoformat() if done else None
    todos_save(items)

def render_open_loops(items=None):
    items = todos_load() if items is None else items
    op = [i for i in items if not i["done"]]
    dn = [i for i in items if i["done"]][-30:]
    md = ["# Open loops\n", "_Auto-captured from check-ins, debriefs, meetings and screen activity. Source in brackets._\n"]
    md += [f"- [ ] {i['text']}  _[{i['source']}, {i['created']}]_" for i in op]
    md += ["\n## Recently done\n"] + [f"- [x] {i['text']}  _({i['done_at']})_" for i in dn]
    (MEM / "open-loops.md").write_text("\n".join(md) + "\n")

def capture_todos(text, source, day=None):
    n = 0
    for m in TODO_RE.finditer(text or ""):
        t = (m.group(1) or m.group(2) or "").strip()
        if todo_add(t[:1].upper() + t[1:], source, day):
            n += 1
    return n

# ---------------------------------------------------------------- curation with citations

EXTRACT_SYS = ("Extract durable facts about the user from new activity. Each input line starts with a source id like "
               "[2026-10-12#3]. Return ONLY JSON with keys: "
               '"projects": [{"name": str, "facts": [str]}], "profile": [str], "goals": [str], '
               '"open_loops": [str], "resolved_loops": [str], "people": [str], "patterns": [str]. '
               "End every fact with its source id(s) in brackets, e.g. 'Chose blue CTA [2026-10-12#3]'. "
               "Facts must be specific (what, which file/site/tool, decision, status, next step) and true to the input. "
               "open_loops = concrete unfinished tasks. Project names short and stable. Empty lists are fine.")

MERGE_SYS = ("You maintain one Markdown file in a personal memory knowledge base. Purpose of this file: {desc}. "
             "Merge the NEW FACTS into the EXISTING FILE: keep everything still true, update status, deduplicate, keep dates "
             "and keep the source ids in brackets (they cite lines in daily logs). Do not invent anything. "
             "Output ONLY the full updated Markdown, under {cap} characters.")

def curate(cfg, new_text):
    out, err = ollama_chat(cfg, EXTRACT_SYS, new_text[:24000])
    if err:
        return f"extract failed: {err}"
    facts = parse_json(out)
    if not isinstance(facts, dict):
        log(f"extract: unparseable JSON: {out[:200]!r}")
        return "extract unparseable"
    touched = []
    for key, fname in {"profile": "profile.md", "goals": "goals.md", "people": "people.md", "patterns": "patterns.md"}.items():
        items = ingest_facts(cfg, key, [str(x) for x in (facts.get(key) or []) if str(x).strip()])
        if items and merge_file(cfg, MEM / fname, CURATED_DESC[fname], items):
            touched.append(fname)
    loops = ingest_facts(cfg, "open_loop", [str(x) for x in facts.get("open_loops") or []])
    for x in loops:
        fdb = facts_db()
        fid = next((f["id"] for f in reversed(fdb["facts"]) if f["kind"] == "open_loop" and f["text"] == x), None)
        if todo_add(re.sub(r"\s*\[[^\]]*\]\s*$", "", str(x)), "ai", fact_id=fid, sources=[s_["cite"] for s_ in resolve_sources(x)]):
            touched.append("todo")
    for x in facts.get("resolved_loops") or []:
        todo_resolve(str(x))
    for pr in facts.get("projects") or []:
        if not isinstance(pr, dict) or not pr.get("name") or not pr.get("facts"):
            continue
        p = MEM / "projects" / f"{slugify(pr['name'])}.md"
        if not p.exists():
            p.write_text(f"# {pr['name']}\n\n## Status\n\n## History & decisions\n\n## Next steps\n")
        pf = ingest_facts(cfg, f"project:{p.stem}", [str(f) for f in pr["facts"]])
        if pf and merge_file(cfg, p, f"history, decisions, status and next steps of the project '{pr['name']}' (with source ids)",
                             pf, cap=cfg["memory_max_chars"] * 2):
            touched.append(f"projects/{p.name}")
            render_project(p.stem)
    return "updated: " + (", ".join(sorted(set(touched))) or "nothing")


# ---------------------------------------------------------------- facts: provenance, two clocks, conflicts, trace
# Curated memories are also kept as structured facts (memory/data/facts.json). The markdown files stay the readable
# view; facts are the ledger: where each memory came from, how sure we are, and when it must be re-checked.

FACT_CITE_RE = re.compile(r"(\d{4}-\d{2}-\d{2})#(\d+)")
CHANGING_RE = re.compile(r"\b(status|deadline|due|by (?:mon|tue|wed|thu|fri|sat|sun)\w*|this (?:week|month|sprint)|today|tomorrow|"
                         r"next week|waiting|blocked|in progress|wip|draft|shipping|launch|release|todo|pending|currently|now|"
                         r"\d{4}-\d{2}-\d{2}|q[1-4]|eta|until)\b", re.I)
PROCESS_RE = re.compile(r"(→|->|\bthen\b.*\bthen\b|\bfollowed by\b|\broutine\b|\bworkflow\b|\bsteps?:|"
                        r"\b(?:every|each) (?:morning|day|evening|monday|tuesday|wednesday|thursday|friday)\b.*\b(?:opens?|checks?|runs?|goes to)\b)", re.I)
STOP = {"the", "a", "an", "to", "of", "for", "my", "on", "with", "and", "is", "are", "was", "be", "in", "at", "it", "this", "that",
        "user", "they", "their", "by", "from", "as", "now", "still"}
NEG_RE = re.compile(r"\b(not|no longer|never|cancel+ed|dropped|abandoned|stopped|isn't|won't|didn't)\b", re.I)
DONE_RE = re.compile(r"\b(done|finished|shipped|completed|launched|merged|closed|resolved)\b", re.I)

def facts_db():
    return jload(DATA / "facts.json", {"facts": [], "conflicts": [], "briefings": []})

def facts_save(db):
    db["briefings"] = db["briefings"][-500:]
    jsave(DATA / "facts.json", db)

def fact_words(t):
    t = FACT_CITE_RE.sub(" ", re.sub(r"\[[^\]]*\]", " ", t.lower()))
    return {w.rstrip(".'-") for w in re.findall(r"[a-z0-9][a-z0-9.+'-]*", t) if w not in STOP and len(w) > 1} - {""}

def strip_cites(t):
    return re.sub(r"\s*\[[^\]]*#\d+[^\]]*\]", "", str(t)).strip()

def resolve_sources(text):
    """Citations like [2026-10-12#3] -> raw log file + line, checked to really exist."""
    out = []
    for day, ln in FACT_CITE_RE.findall(str(text)):
        ok = any(str(e.get("ln")) == ln for e in daily_entries(day))
        out.append({"cite": f"{day}#{ln}", "log": f"daily/.{day}.jsonl", "line": int(ln), "ok": ok})
    return out

def classify_clock(kind, text):
    text = strip_cites(text)
    if kind in ("open_loop",) or kind.startswith("project:"):
        return "changing"
    if kind in ("profile", "people", "patterns"):
        return "changing" if re.search(r"\b(this week|today|tomorrow|currently|deadline|due)\b", text, re.I) else "stable"
    return "changing" if CHANGING_RE.search(text) else "stable"

def is_process(text):
    """Multi-step procedures belong to the automations finder, not to personal memory."""
    return bool(PROCESS_RE.search(text))

def review_date(cfg, clock, today=None):
    today = today or dt.date.today()
    days = cfg.get("fact_review_days_changing", 7) if clock == "changing" else cfg.get("fact_review_days_stable", 120)
    return (today + dt.timedelta(days=days)).isoformat()

def facts_conflict(old, new):
    """Same subject, incompatible claim: different numbers/dates, or one negates/finishes what the other asserts."""
    a, b_ = fact_words(old), fact_words(new)
    if not a or not b_:
        return False
    jac = len(a & b_) / len(a | b_)
    if jac < 0.3:
        return False
    nums = lambda t: set(re.findall(r"\b\d+(?:[.:]\d+)?\b", strip_cites(t))) | \
        set(re.findall(r"\b(?:mon|tues|wednes|thurs|fri|satur|sun)day\b", strip_cites(t).lower()))
    if nums(old) and nums(new) and nums(old) != nums(new):
        return True
    if a == b_:  # same content words = restatement (a one-word swap like blue -> green is NOT)
        return False
    if bool(NEG_RE.search(old)) != bool(NEG_RE.search(new)) or bool(DONE_RE.search(old)) != bool(DONE_RE.search(new)):
        return True
    diff = (a ^ b_)
    return jac >= 0.5 and 0 < len(diff) <= 4 and bool(re.search(r"\b(chose|chosen|picked|decided|uses?|prefers?|switched)\b", old + new, re.I))

def ingest_facts(cfg, kind, items):
    """Record provenance for each new fact. Returns the items that may be merged into markdown: duplicates refresh the
    existing fact, conflicts are parked as questions (never overwrite), and procedures are routed away from memory."""
    db = facts_db()
    today = dt.date.today().isoformat()
    keep = []
    for raw in items:
        text = str(raw).strip()
        if not text:
            continue
        if is_process(text):
            db.setdefault("routed", []).append({"text": strip_cites(text)[:200], "kind": kind, "ts": int(time.time()), "to": "automations"})
            db["routed"] = db["routed"][-200:]
            continue
        srcs = resolve_sources(text)
        live = [f for f in db["facts"] if f["kind"] == kind and f["status"] in ("active", "stale")]
        clash = next((f for f in live if facts_conflict(f["text"], text)), None)
        if clash:
            if not any(c["fact_id"] == clash["id"] and c["status"] == "open" and c["new_text"] == strip_cites(text) for c in db["conflicts"]):
                db["conflicts"].append({"id": secrets.token_hex(4), "fact_id": clash["id"], "old_text": strip_cites(clash["text"]),
                                        "old_sources": [x["cite"] for x in clash["sources"]], "new_text": strip_cites(text),
                                        "new_sources": srcs, "kind": kind, "ts": int(time.time()), "status": "open"})
            continue
        dup = next((f for f in live if difflib.SequenceMatcher(None, strip_cites(f["text"]).lower(), strip_cites(text).lower()).ratio() > 0.9), None)
        if dup:
            known = {x["cite"] for x in dup["sources"]}
            dup["sources"] += [x for x in srcs if x["cite"] not in known]
            dup.update(status="active", review=review_date(cfg, dup["clock"]), verified=today,
                       confidence=round(min(0.95, dup["confidence"] + 0.05 * len([x for x in srcs if x["ok"] and x["cite"] not in known])), 2))
            keep.append(text)
            continue
        good = [x for x in srcs if x["ok"]]
        clock = classify_clock(kind, text)
        db["facts"].append({"id": secrets.token_hex(4), "kind": kind, "text": text, "clock": clock, "sources": srcs,
                            "confidence": round(min(0.95, 0.55 + 0.1 * len(good)) if good else 0.35, 2),
                            "created": today, "verified": today, "review": review_date(cfg, clock), "status": "active", "used_by": []})
        keep.append(text)
    facts_save(db)
    return keep

def recent_evidence(cfg, days=None):
    days = days or cfg.get("fact_recheck_days", 7)
    out = []
    for i in range(days):
        d = (dt.date.today() - dt.timedelta(days=i)).isoformat()
        for e in daily_entries(d):
            txt = " ".join(str(e.get(k, "")) for k in ("title", "summary", "detailed_summary", "text", "notes", "actions"))
            if not blocked(cfg, txt):
                out.append((f"{d}#{e.get('ln')}", txt))
    return out

def recheck_facts(cfg, db=None, today=None):
    """Re-check due 'changing' facts against recent raw logs: refreshed with new evidence, else marked stale."""
    own = db is None
    db = db or facts_db()
    today = today or dt.date.today()
    ev = None
    changed = 0
    for f in db["facts"]:
        if f["status"] != "active" or f["review"] > today.isoformat():
            continue
        if ev is None:
            ev = [(c, fact_words(t)) for c, t in recent_evidence(cfg)]
        w = fact_words(f["text"])
        hit = next((c for c, ew in ev if w and len(w & ew) / len(w) >= 0.6 and c not in {x["cite"] for x in f["sources"]}), None)
        if hit and f["clock"] == "changing":
            f["sources"].append({"cite": hit, "log": f"daily/.{hit.split('#')[0]}.jsonl", "line": int(hit.split("#")[1]), "ok": True})
            f.update(review=review_date(cfg, f["clock"], today), verified=today.isoformat())
        elif f["clock"] == "stable" and not hit:
            f.update(review=review_date(cfg, "stable", today))  # stable facts don't expire for lack of mentions
        else:
            f["status"] = "stale"
            changed += 1
    if own:
        facts_save(db)
    return changed

def facts_for_use(cfg):
    """What briefings / suggestions may rely on: active facts after re-check; stale and disputed ones listed separately."""
    db = facts_db()
    recheck_facts(cfg, db)
    disputed = {c["fact_id"] for c in db["conflicts"] if c["status"] == "open"}
    active = [f for f in db["facts"] if f["status"] == "active" and f["id"] not in disputed]
    stale = [f for f in db["facts"] if f["status"] == "stale" or (f["status"] == "active" and f["id"] in disputed)]
    facts_save(db)
    return db, active, stale

def strip_untrusted(text, bad):
    """Remove markdown lines that carry a stale/disputed/removed fact so it isn't used silently."""
    if not bad:
        return text
    out = []
    for line in text.splitlines():
        lc = strip_cites(line).lstrip("-* ").lower()
        if lc and any(difflib.SequenceMatcher(None, lc, strip_cites(f["text"]).lower()).ratio() > 0.75 for f in bad):
            continue
        out.append(line)
    return "\n".join(out)

def fact_line(f):
    cites = ", ".join(x["cite"] for x in f["sources"][:3]) or "no source"
    return f"- {strip_cites(f['text'])} [{cites}] (confidence {f['confidence']}, review {f['review']})"

def record_use(db, kind, fact_ids, excerpt=""):
    rid = secrets.token_hex(4)
    db["briefings"].append({"id": rid, "kind": kind, "ts": int(time.time()), "fact_ids": sorted(fact_ids), "excerpt": excerpt[:300]})
    for f in db["facts"]:
        if f["id"] in fact_ids:
            f["used_by"] = (f.get("used_by", []) + [rid])[-50:]
    facts_save(db)
    return rid

def fact_trace(fid):
    db = facts_db()
    f = next((x for x in db["facts"] if x["id"] == fid), None)
    if not f:
        raise KeyError("unknown fact")
    cites = {x["cite"] for x in f["sources"]}
    todos = [t for t in todos_load() if t.get("fact_id") == fid or (cites & set(t.get("sources", [])))]
    uses = [b_ for b_ in db["briefings"] if fid in b_["fact_ids"]]
    return {"fact": f, "briefings": uses, "todos": todos,
            "files": [k for k in ([f"projects/{f['kind'][8:]}.md"] if f["kind"].startswith("project:") else [f"{f['kind']}.md"] if f["kind"] != "open_loop" else ["open-loops.md"])]}

def _fact_file(f):
    if f["kind"].startswith("project:"):
        p = MEM / "projects" / f"{slugify(f['kind'][8:])}.md"
    else:
        p = MEM / ("open-loops.md" if f["kind"] == "open_loop" else f"{f['kind']}.md")
    return safe_mem_path(p)

def safe_mem_path(p):
    """Refuse any path that resolves outside the memory folder (path traversal guard)."""
    p = Path(p)
    if MEM.resolve() not in p.resolve().parents:
        raise ValueError(f"path outside memory: {p}")
    return p

def forget_fact(cfg, fid, confirm=False, replacement=None):
    """Bad-memory repair. Without confirm: preview what used it. With confirm: remove (or correct) it in the ledger and the
    markdown, drop to-dos derived from it, and flag the briefings that relied on it."""
    tr = fact_trace(fid)
    if not confirm:
        return dict(tr, preview=True)
    db = facts_db()
    f = next(x for x in db["facts"] if x["id"] == fid)
    p = _fact_file(f)
    if p.exists():
        backup(p)
        lines, out = p.read_text().splitlines(), []
        for line in lines:
            lc = strip_cites(line).lstrip("-* ").lower()
            if lc and difflib.SequenceMatcher(None, lc, strip_cites(f["text"]).lower()).ratio() > 0.75:
                if replacement:
                    out.append(f"- {replacement} [corrected {dt.date.today()}]")
                continue
            out.append(line)
        p.write_text("\n".join(out) + "\n")
    f["status"] = "corrected" if replacement else "removed"
    f["removed"] = dt.date.today().isoformat()
    new = None
    if replacement:
        new = {"id": secrets.token_hex(4), "kind": f["kind"], "text": replacement, "clock": f["clock"],
               "sources": [{"cite": f"user-correction {dt.date.today()}", "log": "", "line": 0, "ok": True}], "confidence": 1.0,
               "created": dt.date.today().isoformat(), "verified": dt.date.today().isoformat(),
               "review": review_date(cfg, f["clock"]), "status": "active", "used_by": [], "corrects": fid}
        db["facts"].append(new)
    for b_ in db["briefings"]:
        if fid in b_["fact_ids"]:
            b_["relied_on_bad_fact"] = True
    for c in db["conflicts"]:
        if c["fact_id"] == fid and c["status"] == "open":
            c["status"] = "resolved-by-correction"
    facts_save(db)
    dropped = [t["id"] for t in tr["todos"]]
    if dropped:
        _todos_save([t for t in todos_load() if t["id"] not in dropped])
    try:
        reindex(cfg)
    except Exception as e:
        log(f"reindex after forget: {e!r}")
    return {"ok": True, "status": f["status"], "briefings_flagged": [b_["id"] for b_ in tr["briefings"]], "todos_removed": dropped,
            "new_fact": new["id"] if new else None}

def resolve_conflict(cfg, cid, choice):
    db = facts_db()
    c = next((x for x in db["conflicts"] if x["id"] == cid), None)
    if not c or c["status"] != "open":
        raise KeyError("unknown or closed conflict")
    if choice not in ("keep", "new", "both"):
        raise ValueError("choice must be keep, new or both")
    c["status"], c["choice"] = "resolved", choice
    facts_save(db)
    if choice == "new":
        forget_fact(cfg, c["fact_id"], confirm=True, replacement=c["new_text"])
    elif choice == "both":
        db = facts_db()
        db["facts"].append({"id": secrets.token_hex(4), "kind": c["kind"], "text": c["new_text"], "clock": classify_clock(c["kind"], c["new_text"]),
                            "sources": c["new_sources"], "confidence": 0.7, "created": dt.date.today().isoformat(),
                            "verified": dt.date.today().isoformat(), "review": review_date(cfg, "changing"), "status": "active", "used_by": []})
        facts_save(db)
    return {"ok": True}

def confirm_fact(cfg, fid):
    db = facts_db()
    f = next(x for x in db["facts"] if x["id"] == fid)
    f.update(status="active", verified=dt.date.today().isoformat(), review=review_date(cfg, f["clock"]),
             confidence=round(min(1.0, f["confidence"] + 0.1), 2))
    f["sources"].append({"cite": f"user-confirmed {dt.date.today()}", "log": "", "line": 0, "ok": True})
    facts_save(db)
    return {"ok": True}

def memory_overview(cfg):
    db, active, stale = facts_for_use(cfg)
    return {"facts": sorted(active, key=lambda f: f["created"], reverse=True)[:300], "stale": stale,
            "conflicts": [c for c in db["conflicts"] if c["status"] == "open"], "routed": db.get("routed", [])[-10:],
            "counts": {"active": len(active), "stale": len(stale), "conflicts": sum(c["status"] == "open" for c in db["conflicts"]),
                       "stable": sum(f["clock"] == "stable" for f in active), "changing": sum(f["clock"] == "changing" for f in active)}}

def conflict_question(c):
    return (f"Earlier memory says “{c['old_text']}” ({', '.join(c['old_sources'][:2]) or 'no source'}), but recent activity says "
            f"“{c['new_text']}” ({', '.join(x['cite'] for x in c['new_sources'][:2]) or 'no source'}). Which is right?")

PERSONAL_EMAIL_RE = re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+")

def scrub_personal(text):
    """Automations get processes only: people's names and emails from memory are masked."""
    t = PERSONAL_EMAIL_RE.sub("<email>", str(text))
    for n in people_names():
        t = re.sub(r"\b" + re.escape(n) + r"\b", "<person>", t)
    return t

# ---------------------------------------------------------------- project autopilot pages

AUTO_START, AUTO_END = "<!-- auto:start -->", "<!-- auto:end -->"

def proj_data(slug):
    p = DATA / f"project-{slug}.json"
    try:
        return json.loads(p.read_text())
    except Exception:
        return {"sessions": [], "files": {}, "urls": {}, "apps": {}}

def proj_save(slug, d):
    DATA.mkdir(parents=True, exist_ok=True)
    (DATA / f"project-{slug}.json").write_text(json.dumps(d, indent=1))

def extract_refs(text):
    urls = set(u.rstrip(".,") for u in URL_RE.findall(text or ""))
    files = set(PATH_RE.findall(text or "")) | set(FILE_RE.findall(text or ""))
    return urls, files, set()

def card_apps(c):
    apps = set()
    m = c.get("metadata")
    try:
        md = json.loads(m) if isinstance(m, str) and m.strip().startswith(("{", "[")) else m
        if isinstance(md, dict):
            for k in ("apps", "app", "appName", "application", "app_sites", "primary_app"):
                v = md.get(k)
                if isinstance(v, str):
                    apps.add(v)
                elif isinstance(v, list):
                    apps.update(str(x if not isinstance(x, dict) else x.get("name") or x.get("app") or "") for x in v)
                elif isinstance(v, dict):
                    apps.update(str(x) for x in v.values() if isinstance(x, str))
    except Exception:
        pass
    known = ["Cursor", "Xcode", "Figma", "Safari", "Chrome", "Arc", "Slack", "Notion", "Terminal", "VS Code", "Mail",
             "Excel", "Word", "Keynote", "Pages", "Numbers", "Zoom", "Obsidian", "Finder", "Photoshop"]
    txt = card_text(c)
    apps.update(a for a in known if re.search(r"\b" + re.escape(a) + r"\b", txt))
    return {a for a in apps if a and len(a) < 40}

def match_projects(c):
    txt = norm(card_text(c))
    out = []
    for p in (MEM / "projects").glob("*.md"):
        words = [w for w in p.stem.split("-") if len(w) > 2]
        if words and sum(w in txt for w in words) >= max(1, (len(words) + 1) // 2):
            out.append(p.stem)
    return out

def track_project_activity(cards):
    touched = set()
    for c in cards:
        for slug in match_projects(c):
            d = proj_data(slug)
            mins = max(0, int(((c.get("end_ts") or 0) - (c.get("start_ts") or 0)) / 60))
            d["sessions"].append({"day": c.get("day"), "start": c.get("start_ts"), "minutes": mins,
                                  "title": c.get("title"), "src": f"{c.get('day')}#{c.get('ln', c.get('id'))}"})
            d["sessions"] = d["sessions"][-300:]
            u, f, _ = extract_refs(card_text(c))
            for k, vals in (("urls", u), ("files", f), ("apps", card_apps(c))):
                for v in vals:
                    d[k][v] = c.get("start_ts") or time.time()
            proj_save(slug, d)
            touched.add(slug)
    for slug in touched:
        render_project(slug)
    return touched

def render_project(slug):
    p = MEM / "projects" / f"{slug}.md"
    if not p.exists():
        return
    d = proj_data(slug)
    body = p.read_text()
    if AUTO_START in body:
        body = body.split(AUTO_START)[0].rstrip() + "\n"
    days = {}
    for s_ in d["sessions"]:
        days[s_["day"]] = days.get(s_["day"], 0) + s_["minutes"]
    recent = sorted(days.items())[-10:]
    top = lambda k, n=15: [x for x, _ in sorted(d[k].items(), key=lambda kv: -kv[1])[:n]]
    fm = lambda m: f"{m // 60}h {m % 60:02d}m" if m >= 60 else f"{m}m"
    auto = [AUTO_START, "## Autopilot (auto-updated)", f"**Total tracked:** {fm(sum(days.values()))} over {len(days)} days",
            "", "### Time by day"] + [f"- [[{k}]]: {fm(v)}" for k, v in recent] + \
           ["", "### Recent sessions"] + [f"- {s_['day']} {hm(s_['start'])} · {fm(s_['minutes'])} · {s_['title']} [{s_['src']}]" for s_ in d["sessions"][-8:]] + \
           ["", "### Files touched"] + [f"- `{x}`" for x in top("files")] + \
           ["", "### Links"] + [f"- {x}" for x in top("urls")] + \
           ["", "### Apps"] + [", ".join(top("apps", 10)) or "-", AUTO_END]
    p.write_text(body + "\n" + "\n".join(auto) + "\n")

# ---------------------------------------------------------------- Obsidian vault (memory/ stays plain markdown)

PERSON_RE = re.compile(r"^\s*[-*]\s*\**\[{0,2}([A-Z][\w.'-]+(?: [A-Z][\w.'-]+)?)\]{0,2}\**\s*(?:[:—–(]|-\s)", re.M)

def people_names():
    names = []
    for n in PERSON_RE.findall(read(MEM / "people.md")):
        if n not in names and n.lower() not in ("people", "none", "unknown"):
            names.append(n)
    return names[:200]

def daily_links(day, items):
    """[[wikilinks]] from a daily note to the projects worked on and people mentioned that day."""
    out = []
    pdir = MEM / "projects"
    for p in sorted(pdir.glob("*.md")) if pdir.exists() else []:
        if any(s_.get("day") == day for s_ in proj_data(p.stem).get("sessions", [])):
            out.append(f"[[{p.stem}]]")
    text = " ".join(str(e.get(k, "")) for e in items for k in ("title", "summary", "text", "notes", "actions"))
    for n in people_names():
        if re.search(r"\b" + re.escape(n) + r"\b", text):
            out.append(f"[[{n}]]")
    return out

def ensure_frontmatter(p, tags, extra=None):
    t = p.read_text() if p.exists() else ""
    if t.startswith("---\n"):
        return False
    fm = "---\ntags: [" + ", ".join(tags) + "]\n" + "".join(f"{k}: {v}\n" for k, v in (extra or {}).items()) + "---\n"
    p.write_text(fm + t)
    return True

def vault_sync(cfg):
    """Make memory/ a valid Obsidian vault: minimal .obsidian config, front-matter tags, people notes with backlinks."""
    if not cfg.get("obsidian_links", True):
        return "obsidian links off"
    ob = MEM / ".obsidian"
    ob.mkdir(exist_ok=True)
    if not (ob / "app.json").exists():
        (ob / "app.json").write_text(json.dumps({"userIgnoreFilters": [".backups/", "data/"], "alwaysUpdateLinks": True}, indent=2))
    if not (ob / "graph.json").exists():
        (ob / "graph.json").write_text(json.dumps({"colorGroups": [
            {"query": "tag:#project", "color": {"a": 1, "rgb": 9333759}}, {"query": "tag:#person", "color": {"a": 1, "rgb": 11832575}},
            {"query": "tag:#daily", "color": {"a": 1, "rgb": 6213786}}]}, indent=2))
    n = 0
    for f in CURATED:
        n += ensure_frontmatter(MEM / f, ["briefing", "curated"])
    for p in (MEM / "projects").glob("*.md"):
        n += ensure_frontmatter(p, ["project"], {"aliases": "[" + p.stem.replace("-", " ").title() + "]"})
    for p in (MEM / "weekly").glob("*.md"):
        n += ensure_frontmatter(p, ["weekly"])
    pdir = MEM / "people"
    pdir.mkdir(exist_ok=True)
    days = sorted((MEM / "daily").glob("*.md"))
    for name in people_names():
        safe = re.sub(r"[^\w .'-]", "", name)
        mentions = [d.stem for d in days if re.search(r"\b" + re.escape(name) + r"\b", d.read_text())][-30:]
        body = (f"---\ntags: [person]\n---\n# {name}\n\n_From [[people]]. Auto-generated; your notes go above the line._\n\n"
                f"{AUTO_START}\n## Mentioned in\n" + "".join(f"- [[{d}]]\n" for d in reversed(mentions)) + AUTO_END + "\n")
        pp = pdir / f"{safe}.md"
        if pp.exists() and AUTO_START in pp.read_text():
            body = pp.read_text().split(AUTO_START)[0] + body[body.index(AUTO_START):]  # keep the user's own notes
        pp.write_text(body)
        n += 1
    people = MEM / "people.md"
    t = people.read_text() if people.exists() else ""
    for name in people_names():  # link names in people.md to their notes, once
        t = re.sub(r"(^\s*[-*]\s*\**)" + re.escape(name) + r"(\**\s*(?:[:—–(]|-\s))", r"\1[[" + name + r"]]\2", t, count=1, flags=re.M)
    if people.exists():
        people.write_text(t)
    return f"vault ok ({n} notes touched)"

# ---------------------------------------------------------------- Things 3 (opt-in)

def things_open(url):
    """Seam for tests. Opens a things:/// URL in the background (no window focus)."""
    if is_mac() and os.environ.get("BRIEFING_TEST_NORUN") != "1":
        subprocess.run(["open", "-g", url], timeout=15)
    return url

def things_add_url(cfg, t):
    q = {"title": t["text"][:250], "notes": f"From Briefing ({t.get('source', '')}). briefing-id:{t['id']}",
         "tags": "Briefing", "reveal": "false"}
    if cfg.get("things_list"):
        q["list"] = cfg["things_list"]
    return "things:///add?" + urllib.parse.urlencode(q, quote_via=urllib.parse.quote)

def things_update_url(cfg, things_id):
    return "things:///update?" + urllib.parse.urlencode({"id": things_id, "auth-token": cfg["things_auth_token"], "completed": "true"},
                                                        quote_via=urllib.parse.quote)

def things_sync(cfg, force=False):
    """Push new open loops to Things (deduped by briefing id); complete them in Things when closed here.
    Completion uses AppleScript (matches the briefing-id in notes; no token needed), or things:///update when the
    Things id is known and an auth token is configured."""
    if not cfg.get("things_sync"):
        return {"skipped": "things_sync is off (enable it in settings)"}
    db = jload(DATA / "things.json", {})
    added = done = 0
    for t in todos_load():
        rec = db.get(t["id"])
        if not t["done"] and not rec:
            if blocked(cfg, t["text"]):
                continue
            things_open(things_add_url(cfg, t))
            db[t["id"]] = {"sent": int(time.time()), "done_sent": False}
            added += 1
        elif t["done"] and rec and not rec.get("done_sent"):
            if rec.get("things_id") and cfg.get("things_auth_token"):
                things_open(things_update_url(cfg, rec["things_id"]))
            elif is_mac() and os.environ.get("BRIEFING_TEST_NORUN") != "1":
                tag = "briefing-id:" + re.sub(r"[^0-9a-f]", "", t["id"])
                subprocess.run(["osascript", "-e", f'tell application "Things3" to set status of (to dos whose notes contains "{tag}") to completed'],
                               capture_output=True, timeout=20)
            rec["done_sent"] = True
            done += 1
    jsave(DATA / "things.json", db)
    return {"added": added, "completed": done}

# ---------------------------------------------------------------- Meetily (local meeting notes)

def meetily_new(cfg, after):
    p = Path(os.path.expanduser(cfg.get("meetily_db", "")))
    if not p.exists():
        return [], None
    try:
        con = sqlite3.connect(f"file:{p}?mode=ro", uri=True, timeout=5)
        con.row_factory = sqlite3.Row
    except Exception as e:
        return [], f"meetily open failed: {e}"
    out = []
    try:
        if not {"id", "title", "created_at", "updated_at"} <= table_cols(con, "meetings"):
            return [], "meetily schema changed"
        for m in con.execute("SELECT id,title,created_at,updated_at FROM meetings WHERE updated_at > ? ORDER BY updated_at", (after,)):
            m = dict(m)
            summ = ""
            if {"meeting_id", "result"} <= table_cols(con, "summary_processes"):
                r = con.execute("SELECT result FROM summary_processes WHERE meeting_id=?", (m["id"],)).fetchone()
                summ = (r[0] or "") if r else ""
                try:
                    j = json.loads(summ)
                    summ = j.get("markdown") or j.get("summary") or json.dumps(j)[:4000] if isinstance(j, dict) else summ
                except Exception:
                    pass
            notes = ""
            if {"meeting_id", "notes_markdown"} <= table_cols(con, "meeting_notes"):
                r = con.execute("SELECT notes_markdown FROM meeting_notes WHERE meeting_id=?", (m["id"],)).fetchone()
                notes = (r[0] or "") if r else ""
            actions, transcript = [], []
            if {"meeting_id", "transcript"} <= table_cols(con, "transcripts"):
                cols = table_cols(con, "transcripts")
                ai = "action_items" if "action_items" in cols else "''"
                for t in con.execute(f"SELECT transcript,{ai} FROM transcripts WHERE meeting_id=? ORDER BY timestamp", (m["id"],)):
                    transcript.append(t[0] or "")
                    if t[1]:
                        actions.append(t[1])
            m.update(summary=summ, notes=notes, actions="\n".join(actions), transcript=" ".join(transcript))
            out.append(m)
        return out, None
    except Exception as e:
        return [], f"meetily read error: {e}"
    finally:
        con.close()

def meeting_ts(m):
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S.%f", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S"):
        try:
            v = dt.datetime.strptime(m["created_at"].replace("Z", "+0000"), fmt)
            return v.timestamp()
        except Exception:
            pass
    return time.time()

# ---------------------------------------------------------------- distill v3

def add_daily(entries):
    """Append entries to the raw daily jsonl (permanent primary record) and re-render markdown.
    Each entry gets a stable line id day#n used for citations."""
    days = {}
    for e in entries:
        day = e.get("day") or dt.date.fromtimestamp(e.get("ts") or time.time()).isoformat()
        e["day"] = day
        days.setdefault(day, []).append(e)
    for day, es in days.items():
        j = MEM / "daily" / f".{day}.jsonl"
        n = len(j.read_text().splitlines()) if j.exists() else 0
        with open(j, "a") as f:
            for e in es:
                n += 1
                e["ln"] = n
                f.write(json.dumps(e) + "\n")
        render_daily(day)
    return set(days)

def render_daily(day):
    j = MEM / "daily" / f".{day}.jsonl"
    items = []
    if j.exists():
        for line in j.read_text().splitlines():
            try:
                items.append(json.loads(line))
            except Exception:
                pass
    items.sort(key=lambda e: (e.get("ts") or 0, e.get("ln") or 0))
    md = [f"---\ntags: [daily]\ndate: {day}\n---", f"# {day}\n", "_Raw activity log (primary record). Ids like #3 are cited by curated notes._\n"]
    for e in items:
        sid = f"#{e.get('ln','?')}"
        if e["type"] == "card":
            md.append(f"### {hm(e.get('start_ts'))}–{hm(e.get('end_ts'))} · {e.get('category','')}"
                      f"{' / ' + e['subcategory'] if e.get('subcategory') else ''} · {e.get('title','')} `{sid}`")
            for k in ("summary", "detailed_summary"):
                if e.get(k):
                    md.append(str(e[k]).strip() + "\n")
            if e.get("metadata"):
                md.append(f"<sub>meta: {str(e['metadata'])[:600]}</sub>\n")
        elif e["type"] == "meeting":
            md.append(f"### 🗓 {hm(e.get('ts'))} Meeting · {e.get('title','')} `{sid}`")
            for k, lab in (("summary", "Summary"), ("notes", "Notes"), ("actions", "Action items")):
                if e.get(k):
                    md.append(f"**{lab}:** {str(e[k]).strip()[:4000]}\n")
            if e.get("transcript"):
                md.append(f"<details><summary>Transcript</summary>\n\n{e['transcript'][:20000]}\n</details>\n")
        else:
            md.append(f"- **{hm(e.get('ts'))} {e.get('kind')}** `{sid}`: {e.get('text','').strip()}\n")
    links = daily_links(day, items)
    if links:
        md.append("\n## Links\n" + " · ".join(links) + "\n")
    (MEM / "daily" / f"{day}.md").write_text("\n".join(md))

def cmd_distill(cfg):
    mem_init()
    st = load_state()
    cards, note = fetch_new_cards(cfg, st.get("wm_card_id", 0), cfg["distill_batch_max_cards"])
    if note:
        log(note)
    events = inbox_since(st.get("wm_inbox_ts", 0))
    meetings, mnote = meetily_new(cfg, st.get("wm_meeting", ""))
    if mnote:
        log(mnote)
    if not cards and not events and not meetings:
        return "nothing new"
    hidden = 0
    keep_cards = []
    for c in cards:
        if blocked(cfg, card_text(c)):
            hidden += 1
        else:
            keep_cards.append(c)
    keep_events = [e for e in events if not blocked(cfg, e.get("text"))]
    keep_meet = [m for m in meetings if not blocked(cfg, card_text(m) + m.get("transcript", ""))]
    hidden += len(events) - len(keep_events) + len(meetings) - len(keep_meet)
    entries = [dict(c, type="card", ts=c.get("start_ts")) for c in keep_cards]
    entries += [dict(e, type="note") for e in keep_events]
    entries += [{"type": "meeting", "ts": meeting_ts(m), "title": m["title"], "summary": m["summary"],
                 "notes": m["notes"], "actions": m["actions"], "transcript": m["transcript"]} for m in keep_meet]
    add_daily(entries)
    st["distill_more"] = len(cards) >= cfg["distill_batch_max_cards"]
    if cards:
        st["wm_card_id"] = max(c["id"] for c in cards)
    if events:
        st["wm_inbox_ts"] = max(e["ts"] for e in events)
    if meetings:
        st["wm_meeting"] = max(m["updated_at"] for m in meetings)
    save_state(st)
    todos = 0
    for e in entries:
        src = f"{e['day']}#{e['ln']}"
        txt = e.get("text") if e["type"] == "note" else (e.get("actions", "") + "\n" + e.get("notes", "") if e["type"] == "meeting" else card_text(e))
        if e["type"] == "card":
            txt = " ".join(str(e.get(k) or "") for k in ("title", "summary", "detailed_summary"))
        todos += capture_todos(txt, src, e["day"])
        if e["type"] == "meeting":
            for line in (e.get("actions") or "").splitlines():
                line = line.strip(" -*•[]0123456789.")
                if len(line) > 5 and todo_add(line, src, e["day"]):
                    todos += 1
    lines = []
    for e in entries:
        sid = f"[{e['day']}#{e['ln']}]"
        if e["type"] == "card":
            lines.append(f"{sid} {hm(e.get('start_ts'))}-{hm(e.get('end_ts'))} {e.get('category','')}: {e.get('title','')}. "
                         f"{e.get('summary') or ''} {(e.get('detailed_summary') or '')[:1200]}")
        elif e["type"] == "meeting":
            lines.append(f"{sid} meeting '{e['title']}': {str(e['summary'])[:1500]} Actions: {e['actions'][:600]}")
        else:
            lines.append(f"{sid} user {e['kind']}: {e['text']}")
    res = curate(cfg, "\n".join(lines))
    pend = MEM / ".pending_curation.txt"
    if not res.startswith("updated"):
        with open(pend, "a") as f:
            f.write("\n".join(lines) + "\n")
    elif pend.exists():
        if curate(cfg, pend.read_text()).startswith("updated"):
            pend.unlink()
    track_project_activity([e for e in entries if e["type"] == "card"])
    reindex(cfg)
    coach = cmd_coach(cfg) if cfg.get("coach_enabled") else "coach off"
    return (f"distilled {len(keep_cards)} cards, {len(keep_events)} notes, {len(keep_meet)} meetings; "
            f"{hidden} hidden by privacy guard; {todos} todos; {res}; coach: {coach}")

# ---------------------------------------------------------------- daily entries helpers / stats

def daily_entries(day):
    j = MEM / "daily" / f".{day}.jsonl"
    out = []
    if j.exists():
        for line in j.read_text().splitlines():
            try:
                out.append(json.loads(line))
            except Exception:
                pass
    return out

def is_distraction(cfg, e):
    cats = {c.lower() for c in cfg.get("coach_distraction_categories", [])}
    if str(e.get("category") or "").lower() in cats or str(e.get("subcategory") or "").lower() in cats:
        return True
    m = str(e.get("metadata") or "").lower()
    return '"distraction' in m and '[]' not in m.split("distraction", 1)[1][:8]

def focus_stats(cfg, days=28, end=None):
    end = end or dt.date.today()
    heat = [[0] * 24 for _ in range(7)]  # [weekday][hour] focus minutes
    dist = [[0] * 24 for _ in range(7)]
    by_cat, total = {}, 0
    for i in range(days):
        d = end - dt.timedelta(days=i)
        for e in daily_entries(d.isoformat()):
            if e.get("type") != "card" or not e.get("start_ts"):
                continue
            s_, t_ = int(e["start_ts"]), int(e.get("end_ts") or e["start_ts"])
            cat = e.get("category") or "Other"
            mins = max(0, (t_ - s_) // 60)
            by_cat[cat] = by_cat.get(cat, 0) + mins
            total += mins
            cur = s_
            while cur < t_:
                lt = dt.datetime.fromtimestamp(cur)
                nxt = min(t_, int((lt.replace(minute=0, second=0) + dt.timedelta(hours=1)).timestamp()))
                m = max(0, (nxt - cur) // 60)
                (dist if is_distraction(cfg, e) else heat)[lt.weekday()][lt.hour] += m
                cur = nxt if nxt > cur else t_
    hours = [sum(heat[w][h] for w in range(7)) for h in range(24)]
    best = sorted(range(24), key=lambda h: -hours[h])[:3]
    return {"heat": heat, "distraction": dist, "by_category": by_cat, "total_minutes": total,
            "best_hours": sorted(h for h in best if hours[h] > 0)}

# ---------------------------------------------------------------- distraction coach

def cmd_coach(cfg):
    st = load_state()
    now = time.time()
    if now - st.get("last_coach", 0) < cfg["coach_cooldown_minutes"] * 60:
        return "cooldown"
    mins, what = 0, {}
    today = dt.date.today().isoformat()
    for e in daily_entries(today):
        if e.get("type") == "card" and is_distraction(cfg, e) and (e.get("end_ts") or 0) > now - 3600:
            m = max(0, (min(e["end_ts"], now) - max(e["start_ts"], now - 3600)) / 60)
            mins += m
            what[e.get("title") or e.get("category")] = what.get(e.get("title") or e.get("category"), 0) + m
    if mins < cfg["coach_threshold_minutes"]:
        return f"ok ({int(mins)} min distracted in last hour)"
    top = max(what, key=what.get) if what else "breaks"
    goal = st.get("session_goal") or "your goal"
    best = focus_stats(cfg, 14)["best_hours"]
    tip = f" Your best focus hours lately: {', '.join(f'{h}:00' for h in best)}." if best else ""
    msg = f"~{int(mins)} min on {top} in the last hour. Want to get back to {goal}?{tip}"
    notify(msg, "Gentle nudge")
    st["last_coach"] = now
    save_state(st)
    return "nudged: " + msg

# ---------------------------------------------------------------- end-of-day debrief

def record_whisper(seconds=60):
    """Optional: record mic with ffmpeg and transcribe with whisper.cpp. Returns text or ''."""
    import shutil
    ff = shutil.which("ffmpeg")
    wc = shutil.which("whisper-cli") or shutil.which("whisper-cpp") or shutil.which("whisper")
    model = next((str(p) for p in [Path("/opt/homebrew/share/whisper-cpp/models/ggml-base.en.bin"),
                                    Path.home() / ".cache/whisper/ggml-base.en.bin"] if p.exists()), None)
    if not (ff and wc and model and is_mac()):
        return ""
    wav = HOME / "debrief.wav"
    notify(f"Recording for {seconds}s… talk now", "Debrief")
    subprocess.run([ff, "-y", "-f", "avfoundation", "-i", ":0", "-t", str(seconds), "-ar", "16000", "-ac", "1", str(wav)],
                   capture_output=True, timeout=seconds + 30)
    r = subprocess.run([wc, "-m", model, "-f", str(wav), "-nt"], capture_output=True, text=True, timeout=300)
    try:
        wav.unlink()
    except Exception:
        pass
    return r.stdout.strip()

def cmd_debrief(cfg):
    today = dt.date.today().isoformat()
    ents = [e for e in daily_entries(today) if e.get("type") == "card"]
    summary = ", ".join(dict.fromkeys(e.get("title", "") for e in ents[-6:])) or "nothing recorded yet"
    prompt = f"End of day debrief. Today you worked on: {summary}. How did it go, what got done, and what's unfinished?"
    cfg2 = dict(cfg, speak=True)
    speak(prompt, cfg2)
    answer = record_whisper() if cfg.get("debrief_use_whisper") else ""
    if not answer:
        answer = ask(prompt + "\n\nTip: use Handy (or macOS Dictation) to speak into this box.", title="Debrief")
    if not answer:
        return "skipped"
    append_log("debrief", answer)
    inbox_add("debrief", answer)
    n = capture_todos(answer, f"{today} debrief", today)
    reply, err = ollama_chat(cfg, "Reply in 2 warm, specific sentences: acknowledge the day and name tomorrow's first step.",
                             f"Activity: {summary}\nUser debrief: {answer}\nOpen loops:\n{read(MEM / 'open-loops.md', 1500)}")
    if reply:
        speak(reply, cfg2)
        notify(reply, "Debrief")
    return f"debrief saved ({n} todos)"

# ---------------------------------------------------------------- weekly "you" report

def cmd_report(cfg, day=None):
    day = day or (dt.datetime.now() - dt.timedelta(hours=6)).date()  # just after midnight still counts as yesterday
    y, w, _ = day.isocalendar()
    this, last = focus_stats(cfg, 7, day), focus_stats(cfg, 7, day - dt.timedelta(days=7))
    todos = todos_load()
    week_ago = (day - dt.timedelta(days=7)).isoformat()
    done = [t["text"] for t in todos if t["done"] and (t["done_at"] or "") >= week_ago]
    opened = [t["text"] for t in todos if t["created"] >= week_ago]
    stats = {"this_week_minutes_by_category": this["by_category"], "last_week_minutes_by_category": last["by_category"],
             "best_focus_hours": this["best_hours"], "todos_done": done[:20], "todos_opened": opened[:20]}
    sys_p = ("Write the user's weekly 'You' report in Markdown: ## Time vs goals (compare where time went with their goals), "
             "## What changed vs last week (use the numbers), ## Wins, ## Best focus hours, ## One experiment for next week "
             "(single, concrete, testable). Warm, honest, specific, under 3500 characters.")
    out, err = ollama_chat(cfg, sys_p, f"Goals:\n{read(MEM / 'goals.md', 2500)}\n\nPatterns:\n{read(MEM / 'patterns.md', 1500)}"
                           f"\n\nStats:\n{json.dumps(stats)}\n\nWeekly rollup:\n{read(MEM / 'weekly' / f'{y}-W{w:02d}.md', 3000)}")
    if err:
        return f"report failed: {err}"
    p = MEM / "weekly" / f"{y}-W{w:02d}-you.md"
    safe_write(p, f"# You, week {w} of {y}\n\n" + out, 5000)
    if cfg.get("phone_push", "off") != "off":
        push(cfg, f"Your week {w}", out)
    notify("Your weekly report is ready", "Dayflow Briefing")
    return f"report {p.name}"

# ---------------------------------------------------------------- forget (privacy)

def parse_when(s, end=False):
    s = s.strip()
    if len(s) == 10:
        d = dt.datetime.strptime(s, "%Y-%m-%d")
        return (d + dt.timedelta(days=1) - dt.timedelta(seconds=1)).timestamp() if end else d.timestamp()
    return dt.datetime.fromisoformat(s).timestamp()

def cmd_forget(cfg, frm, to, rebuild=False):
    t0, t1 = parse_when(frm), parse_when(to, end=True)
    if t1 < t0:
        return "--to is before --from"
    removed = 0
    d = dt.date.fromtimestamp(t0)
    while d <= dt.date.fromtimestamp(t1):
        day = d.isoformat()
        j = MEM / "daily" / f".{day}.jsonl"
        if j.exists():
            keep = []
            for e in daily_entries(day):
                ts = e.get("ts") or e.get("start_ts") or 0
                if t0 <= ts <= t1:
                    removed += 1
                else:
                    keep.append(e)
            if keep:
                j.write_text("".join(json.dumps(e) + "\n" for e in keep))
                render_daily(day)
            else:
                j.unlink()
                (MEM / "daily" / f"{day}.md").unlink(missing_ok=True)
        if t0 <= parse_when(day) and parse_when(day, True) <= t1:
            (LOG_DIR / f"{day}.md").unlink(missing_ok=True)
        d += dt.timedelta(days=1)
    if INBOX.exists():
        lines = [l for l in INBOX.read_text().splitlines() if not (t0 <= json.loads(l).get("ts", 0) <= t1)]
        INBOX.write_text("".join(l + "\n" for l in lines))
    days_in = set()
    d = dt.date.fromtimestamp(t0)
    while d <= dt.date.fromtimestamp(t1):
        days_in.add(d.isoformat()); d += dt.timedelta(days=1)
    whole = {x for x in days_in if t0 <= parse_when(x) and parse_when(x, True) <= t1}
    todos_save([t for t in todos_load() if not any(t["source"].startswith(x) for x in whole) and t["created"] not in whole])
    # remove cited lines from curated + project files; purge backups (they may hold the data)
    cite = re.compile(r"(" + "|".join(re.escape(x) for x in sorted(whole)) + r")") if whole else None
    scrubbed = 0
    if cite:
        for p in list(MEM.glob("*.md")) + list((MEM / "projects").glob("*.md")) + list((MEM / "weekly").glob("*.md")):
            lines = p.read_text().splitlines()
            kept = [l for l in lines if not cite.search(l)]
            if len(kept) != len(lines):
                scrubbed += len(lines) - len(kept)
                p.write_text("\n".join(kept) + "\n")
        for f in DATA.glob("project-*.json"):
            dd = json.loads(f.read_text())
            dd["sessions"] = [s_ for s_ in dd["sessions"] if s_.get("day") not in whole]
            f.write_text(json.dumps(dd))
            render_project(f.stem[len("project-"):])
    for b in (MEM / ".backups").glob("*"):
        b.unlink()
    (MEM / ".pending_curation.txt").unlink(missing_ok=True)
    if rebuild:
        for f in ("profile.md", "goals.md", "people.md", "patterns.md"):
            (MEM / f).unlink(missing_ok=True)
        mem_init()
        for dj in sorted((MEM / "daily").glob(".*.jsonl"))[-14:]:
            day = dj.name[1:-6]
            txt = "\n".join(f"[{day}#{e.get('ln')}] {e.get('title') or e.get('kind','')}: "
                            f"{e.get('summary') or e.get('text') or ''}" for e in daily_entries(day))
            curate(cfg, txt)
    reindex(cfg)
    log(f"forget {frm}..{to}: {removed} entries, {scrubbed} curated lines")
    return (f"forgot {removed} log entries and {scrubbed} cited curated lines from {frm} to {to}; backups purged"
            + ("; curated files rebuilt from remaining logs" if rebuild else
               ". Uncited facts in curated files may remain: use --rebuild to regenerate them.")
            + " Note: Dayflow's own database still has this period (delete it in Dayflow).")

# ---------------------------------------------------------------- hybrid search (FTS5 + embeddings)

def embed(cfg, texts):
    if is_cli(cfg):  # embeddings always come from local Ollama
        cfg = dict(cfg, llm_backend="ollama")
    url = llm_base(cfg) + ("/embeddings" if is_openai(cfg) else "/api/embed")
    body = json.dumps({"model": cfg.get("embed_model", "nomic-embed-text"), "input": texts}).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"}),
                                    timeout=120) as r:
            j = json.loads(r.read())
        v = [d.get("embedding") for d in sorted(j.get("data", []), key=lambda d: d.get("index", 0))] if is_openai(cfg) else j.get("embeddings")
        return v if v and len(v) == len(texts) else None
    except Exception as e:
        log(f"embed unavailable: {e}")
        return None

def reindex(cfg=None):
    MEM.mkdir(parents=True, exist_ok=True)
    old = {}
    if INDEX_DB.exists():
        try:
            c0 = sqlite3.connect(INDEX_DB)
            old = {h: v for h, v in c0.execute("SELECT hash, vec FROM emb")}
            c0.close()
        except Exception:
            pass
    tmp = INDEX_DB.with_suffix(".tmp")
    tmp.unlink(missing_ok=True)
    con = sqlite3.connect(tmp)
    try:
        con.execute("CREATE VIRTUAL TABLE docs USING fts5(path, body)")
        fts = True
    except sqlite3.OperationalError:
        con.execute("CREATE TABLE docs(path TEXT, body TEXT)")
        fts = False
    con.execute("CREATE TABLE emb(rid INTEGER, hash TEXT, vec TEXT)")
    rows = []
    for p in sorted(MEM.rglob("*.md")):
        if ".backups" in p.parts:
            continue
        rel = str(p.relative_to(MEM))
        for ch in _chunks(p.read_text()):
            cur = con.execute("INSERT INTO docs(path, body) VALUES (?, ?)", (rel, ch))
            rows.append((cur.lastrowid, hashlib.sha1(ch.encode()).hexdigest(), ch))
    need = [(r, h, c) for r, h, c in rows if h not in old]
    if cfg and need and cfg.get("embeddings", True):
        for i in range(0, len(need), 32):
            part = need[i:i + 32]
            vecs = embed(cfg, [c[:2000] for _, _, c in part])
            if not vecs:
                break
            for (r, h, _), v in zip(part, vecs):
                old[h] = json.dumps([round(x, 5) for x in v])
    con.executemany("INSERT INTO emb VALUES (?,?,?)", [(r, h, old[h]) for r, h, _ in rows if h in old])
    con.commit()
    con.close()
    os.replace(tmp, INDEX_DB)
    return len(rows), fts

def cosine(a, b):
    num = sum(x * y for x, y in zip(a, b))
    den = math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b)) or 1
    return num / den

def search(query, k=8, cfg=None):
    if not INDEX_DB.exists():
        reindex(cfg)
    con = sqlite3.connect(INDEX_DB)
    ranks = {}
    try:
        words = [w for w in "".join(c if c.isalnum() else " " for c in query.lower()).split() if len(w) > 2]
        stop = {"what", "was", "the", "and", "did", "how", "who", "when", "where", "why", "about", "with", "for",
                "doing", "were", "have", "this", "that", "my", "i"}
        words = [w for w in words if w not in stop] or words
        if words:
            try:
                q = " OR ".join(f'"{w}"' for w in words)
                fts = con.execute("SELECT rowid FROM docs WHERE docs MATCH ? ORDER BY bm25(docs) LIMIT 30", (q,)).fetchall()
            except sqlite3.OperationalError:
                cond = " OR ".join("lower(body) LIKE ?" for _ in words)
                fts = con.execute(f"SELECT rowid FROM docs WHERE {cond} LIMIT 30", [f"%{w}%" for w in words]).fetchall()
            for i, (rid,) in enumerate(fts):
                ranks[rid] = ranks.get(rid, 0) + 1 / (60 + i)
        if cfg:
            qv = embed(cfg, [query])
            if qv:
                sims = [(cosine(qv[0], json.loads(v)), rid) for rid, v in con.execute("SELECT rid, vec FROM emb")]
                floor = cfg.get("embed_min_similarity", 0.45)  # ignore weak semantic matches
                for i, (_, rid) in enumerate(x for x in sorted(sims, reverse=True)[:30] if x[0] >= floor):
                    ranks[rid] = ranks.get(rid, 0) + 1 / (60 + i)
        top = sorted(ranks, key=lambda r: -ranks[r])[:k]
        out = []
        for rid in top:
            r = con.execute("SELECT path, body FROM docs WHERE rowid=?", (rid,)).fetchone()
            if r:
                out.append(r)
        return out
    finally:
        con.close()

def cmd_ask(cfg, question):
    mem_init()
    ctx, used = [], []
    for d in dates_in(question):
        p = MEM / "daily" / f"{d}.md"
        if p.exists():
            ctx.append(f"## daily/{d}.md\n{p.read_text()[:9000]}")
            used.append(f"daily/{d}.md")
    for path, body in search(question, 8, cfg):
        ctx.append(f"## {path}\n{body}")
        used.append(path)
    ctx.append("## goals.md\n" + read(MEM / "goals.md", 1500))
    sys_p = ("Answer the user's question about their own past using ONLY the memory excerpts (daily logs are the primary "
             "record; ids like #3 are log lines). Be specific with times and names. Cite sources as [file#id]. "
             "If the answer isn't there, say you don't have it.")
    out, err = ollama_chat(cfg, sys_p, f"Today is {dt.date.today():%A %Y-%m-%d}.\n\nMEMORY:\n" + "\n\n".join(ctx)[:26000]
                           + f"\n\nQUESTION: {question}")
    if err:
        return f"(Local AI unavailable: {err})\n\nTop matches: " + ", ".join(dict.fromkeys(used)) if used else f"(Local AI unavailable: {err})"
    return out

# ---------------------------------------------------------------- context API (LocalClicky hook)

def context_now(cfg):
    st = load_state()
    today = dt.date.today().isoformat()
    cards = [e for e in daily_entries(today) if e.get("type") == "card"][-3:]
    op = [t["text"] for t in todos_load() if not t["done"]][:5]
    return {"time": dt.datetime.now().isoformat(timespec="minutes"), "session_goal": st.get("session_goal", ""),
            "recent_activity": [f"{hm(c.get('start_ts'))} {c.get('title')}" for c in cards],
            "open_loops": op, "last_briefing": st.get("last_brief_text", "")[:800],
            "text": (f"Goal: {st.get('session_goal') or 'not set'}. Recently: "
                     + "; ".join(c.get("title", "") for c in cards) + ". Open loops: " + "; ".join(op))}

# ---------------------------------------------------------------- resume (reopen last project's stuff)

def resume_targets(cfg):
    projs = sorted(DATA.glob("project-*.json"), key=lambda p: p.stat().st_mtime, reverse=True) if DATA.exists() else []
    if not projs:
        return None
    slug = projs[0].stem[len("project-"):]
    d = proj_data(slug)
    pick = lambda k, n: [x for x, _ in sorted(d.get(k, {}).items(), key=lambda kv: -kv[1])[:n]]
    files = [f for f in pick("files", 6) if f.startswith(("/", "~"))][:3]
    return {"project": slug, "apps": pick("apps", 3), "urls": pick("urls", 3), "files": files}

def do_resume(t):
    opened = []
    for a in t["apps"]:
        if is_mac():
            subprocess.run(["osascript", "-e", f'tell application "{osa_escape(a)}" to activate'], capture_output=True, timeout=20)
        opened.append(a)
    for u in t["urls"] + [os.path.expanduser(f) for f in t["files"] if os.path.exists(os.path.expanduser(f))]:
        if is_mac():
            subprocess.run(["open", u], capture_output=True, timeout=20)
        opened.append(u)
    return opened

def offer_resume(cfg):
    t = resume_targets(cfg)
    if not t or not (t["apps"] or t["urls"] or t["files"]):
        return "nothing to resume"
    listing = "\n".join(["Apps: " + ", ".join(t["apps"])] * bool(t["apps"]) + ["Links: " + ", ".join(t["urls"])] * bool(t["urls"])
                        + ["Files: " + ", ".join(t["files"])] * bool(t["files"]))
    if os.environ.get("BRIEFING_TEST_RESUME") == "yes":
        ok = True
    elif not is_mac():
        print(f"[resume offer] {t['project']}: {listing}")
        return "offered (non-mac)"
    else:
        sc = (f'display dialog "Resume {osa_escape(t["project"])}?\n\n{osa_escape(listing)}" with title "Resume" '
              f'buttons {{"Not now", "Resume"}} default button "Resume" giving up after 300')
        r = subprocess.run(["osascript", "-e", sc], capture_output=True, text=True, timeout=330)
        ok = "Resume" in r.stdout
    return "resumed: " + ", ".join(do_resume(t)) if ok else "declined"

# ---------------------------------------------------------------- briefing v3

def build_context(cfg, cards, journal, standup, note, facts=None):
    parts = [f"Now: {dt.datetime.now():%A %Y-%m-%d %H:%M}"]
    active, stale = facts or ([], [])
    bad = stale + [f for f in facts_db()["facts"] if f["status"] in ("removed", "corrected")]
    for f in ("profile.md", "goals.md"):
        parts.append(f"## {f}\n" + (strip_untrusted(read(MEM / f, 2500), bad) or "(empty)"))
    if active:
        parts.append("## Verified memory facts (source, confidence, review date)\n" + "\n".join(fact_line(f) for f in active[-25:]))
    if stale:
        parts.append("## STALE or disputed memories: do NOT rely on these; if relevant, ask the user to confirm\n" +
                     "\n".join(fact_line(f) for f in stale[:10]))
    bad_ids = {f["id"] for f in bad}
    op = [t for t in todos_load() if not t["done"] and t.get("fact_id") not in bad_ids]
    parts.append("## Open to-dos (auto-captured)\n" + ("\n".join(f"- {t['text']}" for t in op[-15:]) or "(none)"))
    for p in relevant_projects(cards):
        parts.append(f"## projects/{p.name}\n" + strip_untrusted(read(p, 2500), bad))
    ld = last_daily()
    if ld:
        parts.append(f"## Latest raw daily log ({ld.stem}, tail)\n" + read(ld, 3000))
    parts.append("## Today's notes\n" + (read(today_log_path(), 2000) or "(none)"))
    parts.append("## Recent screen activity (Dayflow)\n" + (fmt_cards(cards, 25) or f"(none: {note or 'no cards'})"))
    if standup:
        parts.append("## Dayflow standup\n" + standup.get("payload_json", "")[:1200])
    return "\n\n".join(parts)

def cmd_brief(cfg, force=False, interactive=True):
    st = load_state()
    now = time.time()
    if not force and now - st.get("last_brief", 0) < cfg["cooldown_minutes"] * 60:
        return "cooldown"
    st["last_brief"] = now
    save_state(st)
    mem_init()
    cards, journal, standup, note = fetch_activity(cfg, since_ts=now - cfg["lookback_hours"] * 3600)
    cards = [c for c in cards if not blocked(cfg, card_text(c))]
    if note:
        log(note)
    fdb, active, stale = facts_for_use(cfg)
    refs = [f"memory/projects/{p.name}" for p in relevant_projects(cards)]
    text, err = ollama_chat(cfg, BRIEF_SYS, build_context(cfg, cards, journal, standup, note, (active, stale))[:28000])
    if not err and refs:
        text = text.rstrip() + "\n\nRefs: " + ", ".join(refs + ["memory/open-loops.md"])
    if err:
        log(err)
        op = "\n".join(f"- {t['text']}" for t in todos_load() if not t["done"])[:600]
        text = f"(Local AI unavailable: {err})\n\nOpen loops:\n{op or 'none'}"
    fdb = facts_db()
    conf = [c for c in fdb["conflicts"] if c["status"] == "open"]
    if conf:
        text += "\n\nQuestion for you: " + conflict_question(conf[0]) + (f" (+{len(conf) - 1} more)" if len(conf) > 1 else "") + \
                " Resolve it in the dashboard, Memory tab."
    stale_n = sum(1 for f in fdb["facts"] if f["status"] == "stale")
    if stale_n:
        text += f"\n\n{stale_n} remembered fact(s) are out of date and were not used; confirm or remove them in Memory."
    text = redact(text)
    used = {f["id"] for f in active[-25:]} | {f.get("fact_id") for f in todos_load() if not f["done"] and f.get("fact_id")}
    record_use(fdb, "briefing", {u for u in used if u}, text)
    pend = [p for p in jload(HOME / "improve" / "proposals.json", []) if p.get("status") == "pending"]
    if pend:
        text += f"\n\nSuggested improvement (review it in the dashboard, Improvements tab): {pend[-1]['summary']}"
    st = load_state(); st["last_brief_text"] = text; st["last_brief_at"] = now; save_state(st)
    if interactive:
        show(text)
        speak(text, cfg)
    if cfg.get("push_briefing"):
        push(cfg, "Where you left off", text)
    append_log("briefing", text.replace("\n", " "))
    return "shown" if interactive else text

def cmd_wake(cfg):
    res = cmd_brief(cfg)
    if res == "cooldown":
        return res
    out = [res, offer_resume(cfg)]
    if cfg.get("ask_session_goal"):
        goal = ask("What's your goal for this session?")
        if goal:
            append_log("session goal", goal)
            inbox_add("session goal", goal)
            capture_todos(goal, f"{dt.date.today()} goal")
            st = load_state(); st["session_goal"] = goal; save_state(st)
    return "; ".join(out)

def cmd_checkin(cfg):
    q0, q1 = cfg.get("checkin_quiet_hours", [22, 8])
    h = dt.datetime.now().hour
    quiet = (h >= q0 or h < q1) if q0 > q1 else (q0 <= h < q1)
    if quiet:
        return "quiet"
    goal = load_state().get("session_goal", "")
    a = ask("Check-in: what are you working on, and any blockers?" + (f"\n(Session goal: {goal})" if goal else ""),
            title="Check-in")
    if a:
        append_log("check-in", a)
        inbox_add("check-in", a)
        return "logged"
    return "skipped"

def cmd_nightly(cfg):
    out = [cmd_distill(cfg)]
    for _ in range(200):  # drain the backlog in batches
        if not (out[-1].startswith("distilled") and load_state().get("distill_more")):
            break
        out.append(cmd_distill(cfg))
    out.append(cmd_weekly(cfg, (dt.datetime.now() - dt.timedelta(hours=6)).date()))
    out.append(cmd_cleanup(cfg))
    reindex(cfg)
    try:
        out.append(vault_sync(cfg))
    except Exception as e:
        log(f"vault sync: {e!r}")
    append_log("nightly", "; ".join(out))
    return " | ".join(out)

# ---------------------------------------------------------------- local dashboard + API (127.0.0.1 only)

SETTABLE = {"companion_enabled", "companion_sensitivity", "companion_hint_mode", "companion_study_detection",
            "companion_ocr", "vision_model", "nextmove_enabled", "nextmove_cooldown_minutes", "nextmove_min_confidence", "nextmove_speak",
            "nextmove_focus_minutes", "model", "speak", "voice", "cooldown_minutes", "lookback_hours", "checkin_quiet_hours", "cleanup_enabled",
            "cleanup_min_age_hours", "blocklist", "coach_enabled", "coach_threshold_minutes", "debrief_hour",
            "debrief_use_whisper", "phone_push", "ntfy_topic", "ntfy_server", "imessage_to", "push_briefing",
            "ask_session_goal", "embeddings", "improve_enabled", "improve_auto_apply_params", "improve_code_model",
            "obsidian_links", "things_sync", "things_list", "llm_backend", "cli_model"}

DASH_TIMELINE_MAX = 400

def dashboard_state(cfg):
    st = load_state()
    today = dt.date.today()
    days = sorted(p.stem for p in (MEM / "daily").glob("*.md"))
    day = days[-1] if days else today.isoformat()
    tl = [e for e in daily_entries(day)]
    tl.sort(key=lambda e: e.get("ts") or e.get("start_ts") or 0)
    projects = []
    for p in sorted((MEM / "projects").glob("*.md"), key=lambda p: -p.stat().st_mtime):
        d = proj_data(p.stem)
        projects.append({"slug": p.stem, "md": p.read_text()[:20000],
                         "minutes": sum(s_["minutes"] for s_ in d["sessions"]),
                         "last": max((s_["day"] or "" for s_ in d["sessions"]), default="")})
    weekly = sorted((MEM / "weekly").glob("*-you.md")) or sorted((MEM / "weekly").glob("*.md"))
    stats = focus_stats(cfg, 28)
    return {"now": dt.datetime.now().isoformat(timespec="minutes"), "briefing": st.get("last_brief_text", ""),
            "briefing_at": st.get("last_brief_at"), "session_goal": st.get("session_goal", ""),
            "day": day, "days": days[-30:],
            "timeline_total": len(tl),
            "timeline": [{k: e.get(k) for k in ("type", "ln", "ts", "start_ts", "end_ts", "title", "summary", "category",
                                                 "kind", "text", "detailed_summary")} for e in tl[-DASH_TIMELINE_MAX:]],
            "goals": read(MEM / "goals.md", 8000), "profile": read(MEM / "profile.md", 8000),
            "patterns": read(MEM / "patterns.md", 8000), "people": read(MEM / "people.md", 8000),
            "todos": todos_load(), "projects": projects, "stats": stats,
            "weekly": {"name": weekly[-1].name, "md": weekly[-1].read_text()} if weekly else None,
            "settings": {k: cfg.get(k) for k in sorted(SETTABLE)},
            "watermark": st.get("wm_card_id", 0), "cleanup": read(MEM / "cleanup-report.md", 3000)}

def make_handler(cfg_box):
    html_path = Path(__file__).with_name("dashboard.html")
    port = cfg_box["cfg"]["dashboard_port"]
    allowed_hosts = {f"127.0.0.1:{port}", f"localhost:{port}"}

    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _ok_origin(self):
            # block DNS-rebinding and cross-site requests
            if self.headers.get("Host") not in allowed_hosts:
                return False
            if self.headers.get("Sec-Fetch-Site") in ("cross-site", "same-site"):
                return False
            o = self.headers.get("Origin")
            return o is None or o in {f"http://{h}" for h in allowed_hosts}

        def _send(self, code, body, ctype="application/json"):
            b = body if isinstance(body, bytes) else (json.dumps(body) if ctype == "application/json" else body).encode()
            self.send_response(code)
            self.send_header("Content-Type", ctype + "; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; img-src 'self' data:")
            self.end_headers()
            self.wfile.write(b)

        def _stream(self, gen):
            """NDJSON streaming (one JSON object per line), connection closes at the end."""
            self.send_response(200)
            self.send_header("Content-Type", "application/x-ndjson; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Connection", "close")
            self.end_headers()
            self.close_connection = True
            try:
                for item in gen:
                    self.wfile.write((json.dumps(item) + "\n").encode())
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass

        def do_GET(self):
            if not self._ok_origin():
                return self._send(403, {"error": "forbidden"})
            cfg = cfg_box["cfg"] = load_config()
            path = self.path.split("?")[0]
            if ".." in path or "\\" in path:
                return self._send(400, {"error": "bad path"})
            try:
                if path in ("/", "/index.html"):
                    return self._send(200, html_path.read_bytes(), "text/html")
                if path == "/api/state":
                    return self._send(200, dashboard_state(cfg))
                if path == "/api/context":
                    return self._send(200, context_now(cfg))
                qs = dict(urllib.parse.parse_qsl(self.path.split("?", 1)[1])) if "?" in self.path else {}
                r = ext_get(cfg, path, qs)
                if r is not None:
                    return self._send(200, r)
                if path.startswith("/api/day/"):
                    day = path.rsplit("/", 1)[1]
                    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", day):
                        return self._send(400, {"error": "bad day"})
                    return self._send(200, {"day": day, "timeline": daily_entries(day)})
                return self._send(404, {"error": "not found"})
            except Exception as e:
                telemetry("error", where="GET " + path, error=type(e).__name__)
                log(f"api GET {path}: {e!r}")
                return self._send(500, {"error": str(e)})

        def do_POST(self):
            if not self._ok_origin() or self.headers.get("Content-Type", "").split(";")[0] != "application/json":
                return self._send(403, {"error": "forbidden"})
            cfg = cfg_box["cfg"] = load_config()
            try:
                n = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(min(n, 1_000_000)) or b"{}")
                path = self.path
                if path == "/api/ask":
                    return self._send(200, {"answer": cmd_ask(cfg, str(body.get("q", ""))[:500])})
                if path == "/api/brief":
                    return self._send(200, {"briefing": cmd_brief(cfg, force=True, interactive=False)})
                if path == "/api/todo":
                    if body.get("add"):
                        todo_add(str(body["add"])[:200], "dashboard")
                    elif body.get("id"):
                        todo_set(str(body["id"]), bool(body.get("done")))
                    return self._send(200, {"todos": todos_load()})
                if path == "/api/settings":
                    c = json.loads(CONFIG_PATH.read_text()) if CONFIG_PATH.exists() else {}
                    for k, v in body.items():
                        if k in SETTABLE:
                            c[k] = v
                    CONFIG_PATH.write_text(json.dumps(c, indent=2))
                    return self._send(200, {"ok": True})
                if path == "/api/forget":
                    return self._send(200, {"result": cmd_forget(cfg, str(body["from"]), str(body["to"]), bool(body.get("rebuild")))})
                if path == "/api/resume":
                    t = resume_targets(cfg)
                    if not body.get("confirm"):
                        return self._send(200, {"targets": t})
                    return self._send(200, {"opened": do_resume(t) if t else []})
                if path.split("?")[0] == "/api/answer":
                    return self._stream(answer_stream(cfg, body))
                t0 = time.time()
                r = ext_post(cfg, path.split("?")[0], body)
                if r is not None:
                    telemetry("api", path=path.split("?")[0], ms=int((time.time() - t0) * 1000))
                    return self._send(200, r)
                if path == "/api/distill":
                    return self._send(200, {"result": cmd_distill(cfg)})
                return self._send(404, {"error": "not found"})
            except (KeyError, ValueError, TypeError) as e:
                return self._send(400, {"error": f"bad request: {e}"})
            except Exception as e:
                telemetry("error", where="POST " + self.path.split("?")[0], error=type(e).__name__)
                log(f"api POST {self.path}: {e!r}")
                return self._send(500, {"error": str(e)})
    return H

def cmd_serve(cfg):
    harden_perms()
    class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
        daemon_threads = True
        allow_reuse_address = True
    try:
        srv = S(("127.0.0.1", cfg["dashboard_port"]), make_handler({"cfg": cfg}))
    except OSError as e:
        msg = f"port {cfg['dashboard_port']} in use ({e.strerror}); set dashboard_port in ~/Briefing/config.json"
        job_status("dashboard", False, error=msg)
        log(msg)
        time.sleep(60)  # launchd KeepAlive would otherwise restart us in a tight loop
        return msg
    job_status("dashboard", True, detail=f"listening on 127.0.0.1:{cfg['dashboard_port']}")
    print(f"Dashboard on http://127.0.0.1:{cfg['dashboard_port']}", flush=True)
    srv.serve_forever()

# ======================================================================= v4: automations + next move
AUTO_DIR = HOME / "automations"
AUTO_DB = MEM / "data" / "automations.json"
NM_DB = MEM / "data" / "nextmove.json"
WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
AUTO_EXT = {"applescript": "applescript", "jxa": "js", "shell": "sh", "shortcuts": "md", "playwright": "py"}

def jload(p, default):
    try:
        return json.loads(Path(p).read_text())
    except Exception:
        return default

def jsave(p, d):
    Path(p).parent.mkdir(parents=True, exist_ok=True)
    tmp = Path(str(p) + ".tmp")
    tmp.write_text(json.dumps(d, indent=1))
    os.replace(tmp, p)

def card_token(c):
    apps = sorted(card_apps(c))
    u, _, _ = extract_refs(card_text(c))
    site = sorted(urllib.parse.urlparse(x).netloc for x in u)[:1] if u else []
    if apps:
        return apps[0] + (f" ({site[0]})" if site else "")
    return " ".join(norm(c.get("title") or c.get("category") or "?").split()[:3]) or "?"

def mine_patterns(cfg, days=28, end=None):
    """Find repeated app/site sequences (2-4 steps) and repeated routines across days."""
    import collections
    end = end or dt.date.today()
    seqs, routines = collections.defaultdict(list), collections.defaultdict(list)
    for i in range(days):
        d = end - dt.timedelta(days=i)
        cards = sorted((e for e in daily_entries(d.isoformat()) if e.get("type") == "card" and e.get("start_ts")),
                       key=lambda e: e["start_ts"])
        toks = []
        for c in cards:
            if blocked(cfg, card_text(c)):
                continue
            t = card_token(c)
            mins = max(1, int(((c.get("end_ts") or c["start_ts"]) - c["start_ts"]) / 60))
            if toks and toks[-1][0] == t:
                continue
            toks.append((t, c["start_ts"], mins, f"{d}#{c.get('ln')}"))
            if not is_distraction(cfg, c):
                routines[norm(c.get("title") or "")].append((d, c["start_ts"], mins, c.get("title"), f"{d}#{c.get('ln')}"))
        seen = set()
        for n in (2, 3, 4):
            for j in range(len(toks) - n + 1):
                w = toks[j:j + n]
                key = tuple(x[0] for x in w)
                if len(set(key)) < 2 or (key, d) in seen:
                    continue
                seen.add((key, d))
                seqs[key].append((d, w[0][1], sum(x[2] for x in w), w[0][3]))
    weeks = max(1, days / 7)
    out = []
    def when(occ):
        hrs = collections.Counter(dt.datetime.fromtimestamp(o[1]).hour for o in occ)
        wds = collections.Counter(o[0].weekday() for o in occ)
        h = hrs.most_common(1)[0][0]
        return h, [WEEKDAYS[k] for k, _ in sorted(wds.items())]
    for key, occ in seqs.items():
        if len(occ) < 3:
            continue
        h, wd = when(occ)
        per_week = len(occ) / weeks
        out.append({"kind": "sequence", "steps": list(key), "count": len(occ), "per_week": round(per_week, 1),
                    "hour": h, "weekdays": wd, "sources": [o[3] for o in occ[:5]],
                    "minutes_saved_week": round(per_week * len(key) * 1.5, 1),  # ~1.5 min of switching/opening per step
                    "label": " → ".join(key)})
    # drop sequences fully contained in a longer one that occurs as often
    out = [a for a in out if not any(len(b["steps"]) > len(a["steps"]) and b["count"] >= a["count"]
                                     and " → ".join(a["steps"]) in " → ".join(b["steps"]) for b in out)]
    for key, occ in routines.items():
        if not key or len({o[0] for o in occ}) < 3:
            continue
        h, wd = when(occ)
        per_week = len(occ) / weeks
        avg = sum(o[2] for o in occ) / len(occ)
        out.append({"kind": "routine", "steps": [occ[-1][3]], "count": len(occ), "per_week": round(per_week, 1),
                    "hour": h, "weekdays": wd, "avg_minutes": round(avg), "sources": [o[4] for o in occ[:5]],
                    "minutes_saved_week": round(per_week * min(avg * 0.2, 15), 1),  # assume ~20% of a routine is automatable
                    "label": f"Routine: {occ[-1][3]}"})
    for a in out:
        a["id"] = hashlib.sha1((a["kind"] + a["label"]).encode()).hexdigest()[:10]
    return sorted(out, key=lambda a: -a["minutes_saved_week"])

def automations_refresh(cfg):
    db = jload(AUTO_DB, {"items": {}})
    found = mine_patterns(cfg)
    for a in found:
        cur = db["items"].get(a["id"], {"status": "new", "history": []})
        cur.update({k: v for k, v in a.items()})
        db["items"][a["id"]] = cur
    live = {a["id"] for a in found}
    for k, v in db["items"].items():
        v["stale"] = k not in live
    jsave(AUTO_DB, db)
    return automations_list()

def automations_list():
    db = jload(AUTO_DB, {"items": {}})
    items = list(db["items"].values())
    for it in items:
        if it.get("file") and Path(it["file"]).exists():
            it["script"] = Path(it["file"]).read_text()[:20000]
    return sorted(items, key=lambda a: (a.get("status") == "rejected", a.get("stale", False), -a.get("minutes_saved_week", 0)))

def _auto_set(aid, **kw):
    db = jload(AUTO_DB, {"items": {}})
    it = db["items"].get(aid)
    if not it:
        raise KeyError("unknown automation")
    hist = kw.pop("event", None)
    it.update(kw)
    if hist:
        it.setdefault("history", []).append({"ts": int(time.time()), "event": hist})
    jsave(AUTO_DB, db)
    return it

RISKY = [r"\brm\s+-[a-z]*r", r"\bsudo\b", r"curl[^|\n]*\|\s*(ba)?sh", r"\bmkfs\b", r"\bdd\s+if=", r"delete (every|all)",
         r"\bsend\b.*\b(message|mail)\b", r"\bshutdown\b|\brestart\b", r"\bdefaults\s+delete\b", r"\bkillall\b", r"\bpurchase|\bcheckout\b"]

def lint_script(text):
    return [p for p in RISKY if re.search(p, text or "", re.I)]

DRAFT_SYS = ("You write small, SAFE personal automations for macOS. Given a repeated pattern from the user's activity, "
             "return ONLY JSON: {\"kind\": \"applescript\"|\"jxa\"|\"shell\"|\"shortcuts\"|\"playwright\", \"title\": str, "
             "\"summary\": str (one sentence, what it does), \"script\": str (complete runnable code; for shortcuts: "
             "numbered step-by-step Shortcuts.app instructions), \"test_notes\": str}. Prefer AppleScript to open/arrange "
             "apps, URLs and files; shell for file tasks; playwright (Python, sync API, headful) only for web forms. "
             "Rules: never delete files, send messages/emails, buy anything, or use sudo; be idempotent; add comments; "
             "use only apps/sites from the pattern.")

def automation_draft(cfg, aid, hint=""):
    it = next((a for a in automations_list() if a["id"] == aid), None)
    if not it:
        return {"error": "unknown automation"}
    pat = {k: it.get(k) for k in ("kind", "label", "steps", "hour", "weekdays", "per_week", "avg_minutes")}
    ctx = []
    for src in it.get("sources", [])[:3]:
        day, ln = src.split("#")
        for e in daily_entries(day):
            if str(e.get("ln")) == ln:
                ctx.append(scrub_personal(f"- {e.get('title')}: {e.get('summary') or ''} {str(e.get('detailed_summary') or '')[:300]}"))
    pat = json.loads(scrub_personal(json.dumps(pat)))
    out, err = ollama_chat(cfg, DRAFT_SYS, f"Pattern: {json.dumps(pat)}\nExamples from the log:\n" + "\n".join(ctx)
                           + (f"\nUser hint: {hint}" if hint else ""))
    if err:
        return {"error": err}
    d = parse_json(out)
    if not isinstance(d, dict) or not d.get("script"):
        return {"error": "model returned no script", "raw": out[:500]}
    kind = d.get("kind") if d.get("kind") in AUTO_EXT else "applescript"
    AUTO_DIR.mkdir(parents=True, exist_ok=True)
    f = AUTO_DIR / f"{slugify(d.get('title') or it['label'])[:40]}-{aid}.{AUTO_EXT[kind]}"
    header = {"applescript": "-- ", "jxa": "// ", "shell": "# ", "playwright": "# ", "shortcuts": ""}[kind]
    body = d["script"]
    if kind == "shell" and not body.startswith("#!"):
        body = "#!/bin/bash\nset -euo pipefail\n" + body
    note = f"{header}Drafted by Dayflow Briefing for pattern: {it['label']}\n{header}NOT approved. Review before running.\n"
    if body.startswith("#!"):  # the shebang must stay on line 1
        shebang, _, rest = body.partition("\n")
        f.write_text(shebang + "\n" + note + rest + "\n")
    else:
        f.write_text(note + body + "\n")
    warn = lint_script(body)
    _auto_set(aid, status="drafted", file=str(f), draft_kind=kind, title=d.get("title"), summary=d.get("summary"),
              test_notes=d.get("test_notes"), warnings=warn, approved_hash=None, event="drafted")
    return {"file": str(f), "kind": kind, "summary": d.get("summary"), "warnings": warn}

def automation_dryrun(cfg, aid):
    """Static checks only; never executes the automation."""
    it = next((a for a in automations_list() if a["id"] == aid), None)
    if not it or not it.get("file"):
        return {"ok": False, "log": "draft it first"}
    f, kind = Path(it["file"]), it.get("draft_kind")
    src = f.read_text()
    checks = []
    def run(cmd):
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        return r.returncode == 0, (r.stdout + r.stderr).strip()[:2000]
    import shutil
    if kind in ("applescript", "jxa"):
        if is_mac():
            ok, o = run(["osacompile"] + (["-l", "JavaScript"] if kind == "jxa" else []) + ["-o", "/tmp/briefing-dryrun.scpt", str(f)])
            checks.append(("compile (osacompile, not run)", ok, o))
        else:
            checks.append(("compile", None, "needs macOS osacompile; skipped"))
        if kind == "jxa" and shutil.which("node"):
            ok, o = run(["node", "--check", str(f)])
            checks.append(("JS syntax (node --check)", ok, o))
    elif kind == "shell":
        ok, o = run(["bash", "-n", str(f)])
        checks.append(("bash -n", ok, o))
        if shutil.which("shellcheck"):
            ok, o = run(["shellcheck", "-S", "warning", str(f)])
            checks.append(("shellcheck", ok, o))
    elif kind == "playwright":
        ok, o = run([sys.executable, "-m", "py_compile", str(f)])
        checks.append(("python syntax", ok, o))
    else:
        checks.append(("manual Shortcuts steps", None, "follow the steps in Shortcuts.app"))
    warn = lint_script(src)
    checks.append(("safety lint", not warn, "risky patterns: " + ", ".join(warn) if warn else "no risky patterns found"))
    refs = sorted(set(re.findall(r'application "([^"]+)"', src)) | set(URL_RE.findall(src)))
    ok = all(c[1] is not False for c in checks)
    _auto_set(aid, last_dryrun={"ts": int(time.time()), "ok": ok}, event=f"dry-run {'ok' if ok else 'failed'}")
    return {"ok": ok, "checks": [{"name": n, "ok": k, "out": o} for n, k, o in checks], "would_touch": refs,
            "summary": it.get("summary")}

def automation_decide(aid, decision):
    telemetry("automation", decision=decision)
    if decision == "approve":
        it = next(a for a in automations_list() if a["id"] == aid)
        if not it.get("file"):
            return {"error": "nothing to approve"}
        h = hashlib.sha256(Path(it["file"]).read_bytes()).hexdigest()
        return _auto_set(aid, status="approved", approved_hash=h, event="approved")
    if decision == "reject":
        return _auto_set(aid, status="rejected", approved_hash=None, event="rejected")
    if decision == "reset":
        return _auto_set(aid, status="new", approved_hash=None, event="reset")
    return {"error": "bad decision"}

def automation_run(cfg, aid, confirm=False):
    """Runs only an approved automation whose file is unchanged since approval, and only with confirm=True."""
    it = next((a for a in automations_list() if a["id"] == aid), None)
    if not it or it.get("status") != "approved" or not confirm:
        return {"ok": False, "log": "not approved or not confirmed; nothing ran"}
    f = Path(it["file"])
    if hashlib.sha256(f.read_bytes()).hexdigest() != it.get("approved_hash"):
        _auto_set(aid, status="drafted", approved_hash=None, event="file changed; approval revoked")
        return {"ok": False, "log": "file changed since approval; re-approve it"}
    kind = it.get("draft_kind")
    if kind in ("applescript", "jxa"):
        if not is_mac():
            return {"ok": False, "log": "needs macOS"}
        cmd = ["osascript"] + (["-l", "JavaScript"] if kind == "jxa" else []) + [str(f)]
    elif kind == "shell":
        cmd = ["bash", str(f)]
    elif kind == "playwright":
        cmd = [sys.executable, str(f)]
    else:
        return {"ok": False, "log": "Shortcuts instructions are manual"}
    if os.environ.get("BRIEFING_TEST_NORUN"):
        r = subprocess.CompletedProcess(cmd, 0, "test: not executed", "")
    else:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    _auto_set(aid, runs=it.get("runs", 0) + 1, event=f"ran (exit {r.returncode})")
    return {"ok": r.returncode == 0, "log": (r.stdout + r.stderr)[-3000:]}

# ---------------------------------------------------------------- next move (Clicky-style companion brain)

def idle_seconds():
    if "BRIEFING_TEST_IDLE" in os.environ:
        return float(os.environ["BRIEFING_TEST_IDLE"])
    if not is_mac():
        return 0.0
    try:
        out = subprocess.run(["ioreg", "-c", "IOHIDSystem"], capture_output=True, text=True, timeout=5).stdout
        m = re.search(r'"HIDIdleTime" = (\d+)', out)
        return int(m.group(1)) / 1e9 if m else 0.0
    except Exception:
        return 0.0

def recent_cards(n=10):
    out = []
    for i in (1, 0):
        out += [e for e in daily_entries((dt.date.today() - dt.timedelta(days=i)).isoformat()) if e.get("type") == "card"]
    return sorted(out, key=lambda e: e.get("start_ts") or 0)[-n:]

def in_deep_focus(cfg, now=None):
    now = now or time.time()
    span, t = 0, now
    for c in reversed(recent_cards(10)):
        if is_distraction(cfg, c) or (c.get("end_ts") or 0) < t - 600:
            break
        span += max(0, (c.get("end_ts") or 0) - (c.get("start_ts") or 0))
        t = c.get("start_ts") or t
    return span >= cfg.get("nextmove_focus_minutes", 25) * 60

def nm_gate(cfg, trigger, now=None):
    now = now or time.time()
    if not cfg.get("nextmove_enabled", True):
        return False, "disabled"
    q0, q1 = cfg.get("checkin_quiet_hours", [22, 8])
    h = dt.datetime.fromtimestamp(now).hour
    if (h >= q0 or h < q1) if q0 > q1 else (q0 <= h < q1):
        return False, "quiet hours"
    if idle_seconds() > cfg.get("nextmove_idle_seconds", 300):
        return False, "user idle"
    db = jload(NM_DB, {})
    cool = cfg.get("nextmove_cooldown_minutes", 10) * 60 * (2 ** min(db.get("dismiss_streak", 0), 4))
    if now - db.get("last_shown", 0) < cool:
        return False, f"cooldown ({int(cool / 60)} min)"
    if trigger != "app_switch" and in_deep_focus(cfg, now):
        return False, "deep focus"
    return True, "ok"

NM_SYS = ("You are a quiet desktop companion. From the user's recent activity, routines and open loops, predict the ONE "
          "most likely next thing they want to do in the next few minutes, and offer up to 3 one-tap actions. "
          "Return ONLY JSON: {\"intent\": str|null, \"why\": str, \"confidence\": 0..1, \"say\": str, \"actions\": "
          "[{\"type\": \"open_app\"|\"open_url\"|\"open_file\"|\"run_automation\"|\"add_todo\", \"target\": str, \"label\": str}]}. "
          "Use only apps, URLs, files and automation ids that appear in the context. If nothing useful, return "
          "{\"intent\": null}. Interrupting is costly: only suggest when confident.")

def nm_context(cfg, app=None):
    now = dt.datetime.now()
    cards = recent_cards(10)
    autos = [a for a in automations_list() if a.get("status") != "rejected"][:8]
    approved = [a for a in autos if a.get("status") == "approved"]
    lines = [f"Now: {now:%A %H:%M}" + (f"; frontmost app: {app}" if app else ""),
             "## Recent activity"] + [f"- {hm(c.get('start_ts'))}-{hm(c.get('end_ts'))} {c.get('title')} "
                                      f"(apps: {', '.join(sorted(card_apps(c))) or '-'}) {extract_refs(card_text(c))[0] or ''}" for c in cards]
    fdb, _active, stale = facts_for_use(cfg)
    bad = stale + [f for f in fdb["facts"] if f["status"] in ("removed", "corrected")]
    bad_ids = {f["id"] for f in bad}
    lines += ["## Profile", strip_untrusted(read(MEM / "profile.md", 1200), bad), "## Open loops"] + \
             [f"- {t['text']}" for t in todos_load() if not t["done"] and t.get("fact_id") not in bad_ids][:10]
    lines += ["## Learned routines (pattern, usual hour, weekdays)"] + \
             [f"- {a['label']} ~{a.get('hour')}:00 {','.join(a.get('weekdays', []))}" for a in autos]
    lines += ["## Approved automations (id: title)"] + [f"- {a['id']}: {a.get('title') or a['label']}" for a in approved]
    t = resume_targets(cfg)
    if t:
        lines += [f"## Last project {t['project']}: apps {t['apps']}, urls {t['urls']}, files {t['files']}"]
    return "\n".join(lines), {a["id"] for a in approved}

def nm_validate(pred, approved_ids, ctx_text):
    acts = []
    for a in (pred.get("actions") or [])[:8]:
        if len(acts) >= 3:
            break
        if not isinstance(a, dict):
            continue
        ty, tg = a.get("type"), str(a.get("target") or "")
        ok = (ty == "open_app" and tg and tg in ctx_text) or \
             (ty == "open_url" and tg.startswith(("https://", "http://"))) or \
             (ty == "open_file" and os.path.exists(os.path.expanduser(tg))) or \
             (ty == "run_automation" and tg in approved_ids) or \
             (ty == "add_todo" and 3 < len(tg) < 200)
        if ok:
            acts.append({"type": ty, "target": tg, "label": str(a.get("label") or tg)[:60]})
    return acts

def predict_next(cfg, trigger="tick", app=None, force=False):
    db = jload(NM_DB, {})
    if not force:
        ok, why = nm_gate(cfg, trigger)
        if not ok:
            return {"intent": None, "gated": why}
    if blocked(cfg, app or ""):
        return {"intent": None, "gated": "blocked app"}
    now = time.time()
    if not force:  # rate-limit model calls even when nothing gets shown
        gap = cfg.get("nextmove_interval_minutes", 4) * 60 if trigger not in ("app_switch",) else 60
        if now - db.get("last_attempt", 0) < gap:
            return {"intent": None, "gated": "rate limited"}
    db["last_attempt"] = now
    jsave(NM_DB, db)
    ctx, approved = nm_context(cfg, app)
    out, err = ollama_chat(cfg, NM_SYS, ctx[:12000])
    if err:
        return {"intent": None, "gated": f"model unavailable: {err}"}
    p = parse_json(out)
    if not isinstance(p, dict) or not p.get("intent"):
        return {"intent": None, "gated": "model: nothing useful"}
    conf = float(p.get("confidence") or 0)
    acts = nm_validate(p, approved, ctx)
    kind = acts[0]["type"] if acts else "none"
    st = db.get("stats", {}).get(kind, {"accept": 0, "dismiss": 0})
    n = st["accept"] + st["dismiss"]
    need = cfg.get("nextmove_min_confidence", 0.55)
    if n >= 5 and st["accept"] / n < 0.2:
        need = max(need, 0.8)   # learned: this kind of suggestion is usually dismissed
    if conf < need and not force:
        return {"intent": None, "gated": f"low confidence {conf:.2f} < {need:.2f}"}
    pred = {"id": secrets.token_hex(5), "intent": str(p["intent"])[:140], "why": str(p.get("why") or "")[:240],
            "say": str(p.get("say") or p["intent"])[:200], "confidence": conf, "actions": acts, "kind": kind,
            "created": int(time.time()), "trigger": trigger, "speak": bool(cfg.get("nextmove_speak"))}
    db["last"], db["last_shown"] = pred, time.time()
    jsave(NM_DB, db)
    return pred

def perform_action(cfg, a):
    ty, tg = a["type"], a["target"]
    if ty == "add_todo":
        return "added" if todo_add(tg, "next-move") else "duplicate"
    if ty == "run_automation":
        return automation_run(cfg, tg, confirm=True).get("log", "")[:300]
    if not is_mac():
        return f"(non-mac) would {ty} {tg}"
    if ty == "open_app":
        subprocess.run(["osascript", "-e", f'tell application "{osa_escape(tg)}" to activate'], capture_output=True, timeout=20)
    else:
        subprocess.run(["open", os.path.expanduser(tg)], capture_output=True, timeout=20)
    return f"{ty} {tg}"

def nm_feedback(cfg, pid, outcome, action_index=None):
    db = jload(NM_DB, {})
    pred = db.get("last") or {}
    if pred.get("id") != pid:
        return {"error": "unknown or expired prediction"}
    kind = pred.get("kind", "none")
    st = db.setdefault("stats", {}).setdefault(kind, {"accept": 0, "dismiss": 0})
    result = None
    if outcome == "accept":
        st["accept"] += 1
        db["dismiss_streak"] = 0
        acts = pred.get("actions") or []
        if action_index is not None and 0 <= int(action_index) < len(acts):
            result = perform_action(cfg, acts[int(action_index)])
    else:
        st["dismiss"] += 1
        db["dismiss_streak"] = db.get("dismiss_streak", 0) + 1
    db.setdefault("history", []).append({"ts": int(time.time()), "intent": pred.get("intent"), "outcome": outcome, "kind": kind,
                                         "confidence": pred.get("confidence")})
    telemetry("nextmove", outcome=outcome, nm_kind=kind, confidence=pred.get("confidence"))
    db["history"] = db["history"][-200:]
    db["last"] = None
    jsave(NM_DB, db)
    return {"ok": True, "result": result, "stats": db["stats"], "dismiss_streak": db.get("dismiss_streak", 0)}

# ======================================================================= v5: anticipatory companion (any activity)
import difflib

COMP_DB = MEM / "data" / "companion.json"

# Pluggable activity modes. Each profile: how to detect it, what "stuck" looks like, how people phrase
# questions there, and how answers should be shaped. Add a mode by adding a dict entry.
MODES = {
    "study": {"apps": [], "sites": [], "title": ["lecture", "homework", "problem set", "pset", "chapter", "exam", "quiz", "syllabus", "worksheet", "textbook", "course"],
              "text": [r"\bexercise\s+\d", r"\btheorem\b", r"\bproof\b", r"∫|∑|√|≤|≥|∂", r"\bsolve\b.*\bfor\b", r"\bproblem\s+\d", r"\blemma\b", r"\bdefinition\b"],
              "weights": {"rereads": 1.6, "dwell": 1.2}, "dwell_ref": 300, "answer": "hints", "pointer": True,
              "style": "conceptual and step questions, e.g. 'How do I get from step 2 to step 3?', 'What does <term> mean here?', 'Why is <claim> true?'"},
    "coding": {"apps": ["Xcode", "Cursor", "Code", "Visual Studio Code", "PyCharm", "IntelliJ IDEA", "Terminal", "iTerm2", "Warp", "Zed", "Nova", "Sublime Text", "Android Studio"],
               "sites": ["github.com", "gitlab.com", "stackoverflow.com", "developer.apple.com", "docs.python.org", "developer.mozilla.org"],
               "title": [".py", ".ts", ".tsx", ".js", ".swift", ".go", ".rs", ".java", ".kt", ".rb", ".c", ".cpp", "pull request"],
               "text": [r"Traceback \(most recent call last\)", r"\b(?:Error|Exception|error:|warning:)", r"\bdef |\bfunc |\bclass |\bimport |=>|\bconst ", r"\bnpm ERR!|\bpanic:|\bSegmentation fault"],
               "weights": {"errors": 2.0, "search": 1.3}, "dwell_ref": 420, "answer": "fix", "pointer": True,
               "style": "debugging questions, e.g. 'Why is this throwing <error>?', 'How do I fix this type error?', 'What does this function return?'"},
    "writing": {"apps": ["Pages", "Microsoft Word", "Word", "Google Docs", "Ulysses", "iA Writer", "Bear", "Scrivener", "Craft", "TextEdit"],
                "sites": ["docs.google.com/document", "medium.com/new-story", "substack.com"], "title": ["draft", "essay", "blog", "proposal", "cover letter", "report"],
                "text": [r"\b(?:Dear|Sincerely|Introduction|Conclusion|Abstract)\b"],
                "weights": {"low_progress": 1.8, "dwell": 1.0}, "dwell_ref": 360, "answer": "rewrite", "pointer": False,
                "style": "phrasing questions, e.g. 'How can I say this more clearly?', 'How do I open this paragraph?', 'Is this too long?'"},
    "design": {"apps": ["Figma", "Sketch", "Adobe Photoshop", "Photoshop", "Adobe Illustrator", "Illustrator", "Affinity Designer", "Pixelmator Pro", "Framer", "Blender", "Canva"],
               "sites": ["figma.com", "canva.com"], "title": ["frame", "artboard", "mockup"], "text": [r"\bAuto layout\b|\bConstraints\b|\bLayers\b"],
               "weights": {"dwell": 1.0, "search": 1.2}, "dwell_ref": 360, "answer": "steps", "pointer": True,
               "style": "tool-how-to questions, e.g. 'How do I make this auto-layout hug contents?', 'How do I align these?'"},
    "spreadsheets": {"apps": ["Microsoft Excel", "Excel", "Numbers", "Google Sheets"], "sites": ["docs.google.com/spreadsheets", "airtable.com"],
                     "title": [".xlsx", ".csv", "sheet"], "text": [r"#(?:REF|VALUE|N/A|DIV/0|NAME)!?", r"=\s*(?:SUM|VLOOKUP|XLOOKUP|INDEX|IF|COUNTIF)\(", r"\bA1\b|\bB\d+\b"],
                     "weights": {"errors": 2.0, "dwell": 1.1}, "dwell_ref": 300, "answer": "formula", "pointer": True,
                     "style": "formula questions, e.g. 'How do I look up X in sheet 2?', 'Why does this show #REF!?', 'How do I sum by month?'"},
    "email": {"apps": ["Mail", "Outlook", "Microsoft Outlook", "Spark", "Superhuman", "Mimestream"], "sites": ["mail.google.com", "outlook.live.com", "outlook.office.com"],
              "title": ["inbox", "re:", "fwd:"], "text": [r"^(?:From|To|Subject):", r"\bReply\b.*\bForward\b"],
              "weights": {"low_progress": 1.5}, "dwell_ref": 240, "answer": "rewrite", "pointer": False,
              "style": "reply questions, e.g. 'How do I politely say no?', 'What should I reply to this?'"},
    "research": {"apps": ["Safari", "Google Chrome", "Arc", "Firefox", "Brave Browser", "Microsoft Edge"], "sites": ["wikipedia.org", "scholar.google", "arxiv.org", "news.ycombinator.com", "reddit.com"],
                 "title": ["wikipedia", "arxiv", "research", "paper"], "text": [r"\bAbstract\b|\bReferences\b|\bet al\.\b"],
                 "weights": {"rereads": 1.2, "search": 0.8}, "dwell_ref": 300, "answer": "direct", "pointer": True,
                 "style": "summary questions, e.g. 'What's the key claim here?', 'How does this compare to X?'"},
    "shopping": {"apps": [], "sites": ["amazon.", "ebay.", "etsy.com", "bestbuy.com", "walmart.com", "target.com", "apple.com/shop", "aliexpress"],
                 "title": ["cart", "checkout", "buy", "price"], "text": [r"\bAdd to (?:Cart|Bag)\b|\$\d+(?:\.\d\d)?|\bfree shipping\b|\breviews?\b"],
                 "weights": {"search": 1.4, "rereads": 1.2}, "dwell_ref": 240, "answer": "direct", "pointer": True,
                 "style": "comparison questions, e.g. 'Which of these is better value?', 'Is this compatible with my Mac?'"},
    "admin": {"apps": ["System Settings", "System Preferences", "Finder", "Keychain Access", "Disk Utility", "1Password"], "sites": ["irs.gov", "gov.", "login", "signin", "account", "billing", "dmv"],
              "title": ["settings", "preferences", "form", "application", "account", "billing", "tax"],
              "text": [r"\brequired\b|\binvalid\b|\bSubmit\b|\bContinue\b|\bpassword\b|\bverify\b|\berror\b"],
              "weights": {"errors": 1.6, "dwell": 1.1}, "dwell_ref": 180, "answer": "steps", "pointer": True,
              "style": "navigation questions, e.g. 'Where do I change X?', 'What goes in this field?', 'Why won't this submit?'"},
    "video": {"apps": ["Final Cut Pro", "iMovie", "DaVinci Resolve", "Adobe Premiere Pro", "Logic Pro", "GarageBand", "CapCut", "ScreenFlow"], "sites": [],
              "title": ["timeline", "project", "render"], "text": [r"\bTimeline\b|\bInspector\b|\bKeyframe\b|\bExport\b"],
              "weights": {"dwell": 1.0, "search": 1.3}, "dwell_ref": 420, "answer": "steps", "pointer": True,
              "style": "editing how-to questions, e.g. 'How do I cut this clip?', 'How do I fade the audio?'"},
    "meetings": {"apps": ["zoom.us", "Zoom", "Microsoft Teams", "Teams", "FaceTime", "Webex", "Slack"], "sites": ["meet.google.com", "teams.microsoft.com", "zoom.us/j"],
                 "title": ["meeting", "call", "huddle"], "text": [r"\bMute\b|\bLeave\b|\bShare Screen\b|\bParticipants\b"],
                 "weights": {"idle": 0.2, "dwell": 0.3}, "dwell_ref": 1800, "answer": "direct", "pointer": False,
                 "style": "quick context questions, e.g. 'What did they mean by <term>?', 'What was decided earlier?'"},
    "unknown": {"apps": [], "sites": [], "title": [], "text": [], "weights": {}, "dwell_ref": 300, "answer": "steps", "pointer": True,
                "style": "goal questions, e.g. 'What am I trying to do here and what's the next step?', 'How do I do <visible task> in this app?'"},
}
ERROR_RE = re.compile(r"\b(?:error|exception|failed|invalid|not found|denied|undefined|traceback)\b|#(?:REF|VALUE|N/A|DIV/0|NAME)", re.I)

def detect_mode(cfg, sig):
    app = str(sig.get("app") or "")
    title = str(sig.get("window_title") or "").lower()
    url = str(sig.get("url") or "").lower()
    text = str(sig.get("screen_text") or "")[:8000]
    scores = {}
    for name, p in MODES.items():
        if name == "unknown" or (name == "study" and not cfg.get("companion_study_detection", True)):
            continue
        apps = p["apps"] + (cfg.get("companion_study_apps", []) if name == "study" else [])
        sites = p["sites"] + (cfg.get("companion_study_sites", []) if name == "study" else [])
        sc = 3 * any(a.lower() == app.lower() for a in apps)
        sc += 3 * any(x in url for x in sites if x)
        sc += min(2, sum(k in title for k in p["title"]))
        sc += min(3, sum(1 for rx in p["text"] if re.search(rx, text, re.I | re.M)))
        scores[name] = sc
    # PDFs/notes readers with study-ish text count as studying even when the app is generic
    if scores.get("study", 0) and (title.endswith(".pdf") or ".pdf" in url):
        scores["study"] += 2
    best = max(scores, key=scores.get) if scores else "unknown"
    if scores.get(best, 0) < 3:
        return "unknown", scores
    return best, scores

SUBJECTS = {"calculus": r"∫|\bderivative|\bintegral|\blimit\b|\bd/dx", "linear algebra": r"\bmatrix|\beigen|\bvector space",
            "statistics": r"\bp-value|\bregression|\bvariance|\bdistribution", "physics": r"\bmomentum|\bnewton|\bvelocity|\bjoule",
            "chemistry": r"\bmolar|\breaction|\bstoichiometr|\bpH\b", "programming": r"\bfunction|\balgorithm|\bcomplexity",
            "biology": r"\bcell|\bprotein|\bDNA\b", "economics": r"\bdemand|\bsupply|\belasticity"}
LANGS = {".py": "Python", ".ts": "TypeScript", ".tsx": "TypeScript", ".js": "JavaScript", ".swift": "Swift", ".go": "Go",
         ".rs": "Rust", ".java": "Java", ".kt": "Kotlin", ".rb": "Ruby", ".cpp": "C++", ".c": "C"}

def detect_subject(mode, sig):
    text, title = str(sig.get("screen_text") or ""), str(sig.get("window_title") or "")
    if mode == "study":
        for subj, rx in SUBJECTS.items():
            if re.search(rx, text + " " + title, re.I):
                return subj
    if mode == "coding":
        m = re.search(r"(\.\w{1,5})\b", title)
        if m and m.group(1) in LANGS:
            return LANGS[m.group(1)]
        if "Traceback" in text or re.search(r"\bdef \w+\(", text):
            return "Python"
    return ""

def stuck_score(cfg, sig, mode):
    """0..1 likelihood the user is stuck, with human-readable reasons. Only behavioural counters are used;
    no keystroke contents ever leave the companion."""
    p = MODES[mode]
    w = dict({"dwell": 1, "scroll": 1, "rereads": 1, "search": 1, "idle": 1, "low_progress": 1, "long": 1, "errors": 1}, **p["weights"])
    f = lambda k, d=0: float(sig.get(k) or d)
    dwell, idle = f("dwell_s"), f("idle_s")
    parts = {
        "dwell": (0.22 * min(dwell / p["dwell_ref"], 1), f"on the same {('page' if mode in ('research', 'study', 'shopping') else 'window')} for {int(dwell // 60)} min"),
        "scroll": (0.12 * min(f("scroll_reversals") / 6, 1), f"scrolled back and forth {int(f('scroll_reversals'))}×"),
        "rereads": (0.12 * min(f("rereads") / 3, 1), f"re-read the same part {int(f('rereads'))}×"),
        "search": (0.18 * min(f("search_switches") / 2, 1), f"switched to search/AI {int(f('search_switches'))}×"),
        "idle": (0.10 * (1 if sig.get("present") and 20 <= idle <= 240 else 0), f"paused {int(idle)}s while still here"),
        "low_progress": (0.10 * (1 if dwell > 90 and f("typing_cpm", 999) < 15 else 0), "little typing or progress"),
        "long": (0.08 * min(f("time_on_task_s") / 1200, 1), f"{int(f('time_on_task_s') // 60)} min on this task"),
        "errors": (0.08 * (1 if ERROR_RE.search(str(sig.get("screen_text") or "") + " " + str(sig.get("window_title") or "")) else 0), "an error is visible"),
    }
    total, reasons = 0.0, []
    for k, (v, why) in parts.items():
        v *= w.get(k, 1)
        total += v
        if v >= 0.05:
            reasons.append((v, why))
    return round(min(total, 1.0), 3), [r for _, r in sorted(reasons, reverse=True)[:3]]

def comp_load():
    return jload(COMP_DB, {"pending": {}, "events": [], "last_by_window": {}})

def comp_save(db):
    db["events"] = db["events"][-2000:]
    if len(db["pending"]) > 200:
        for k in sorted(db["pending"], key=lambda k: db["pending"][k]["ts"])[:-200]:
            db["pending"].pop(k)
    jsave(COMP_DB, db)

def mode_threshold(cfg, db, mode):
    sens = min(max(float(cfg.get("companion_sensitivity", 0.6)), 0.0), 1.0)
    th = float(cfg.get("companion_threshold_base", 0.75)) - 0.45 * sens
    recent = [e for e in db["events"][-60:] if e["mode"] == mode]
    if len(recent) >= 6 and sum(e["outcome"] in ("ignored", "dismissed") for e in recent) / len(recent) > 0.7:
        th += float(cfg.get("companion_ignore_backoff", 0.12))  # learned: in this mode the user usually waves us off
    return min(th, 0.95)

def few_shots(db, mode, app, k=4):
    finals = [e for e in reversed(db["events"]) if e.get("final") and e["outcome"] in ("chosen", "edited", "typed")]
    same = [e for e in finals if e["mode"] == mode and e.get("app") == app]
    other = [e for e in finals if e["mode"] == mode and e.get("app") != app]
    out, seen = [], set()
    for e in same + other:
        if e["final"].lower() not in seen:
            seen.add(e["final"].lower()); out.append(e)
        if len(out) >= k:
            break
    return out

def style_summary(db, mode):
    finals = [e["final"] for e in db["events"] if e["mode"] == mode and e.get("final")][-40:]
    if len(finals) < 3:
        return ""
    import collections
    starts = collections.Counter(" ".join(f.split()[:2]).lower() for f in finals).most_common(3)
    avg = sum(len(f.split()) for f in finals) / len(finals)
    return f"This user's questions here average {avg:.0f} words and often start with: " + ", ".join(f"'{s}'" for s, _ in starts) + "."

ANTICIPATE_SYS = ("You anticipate what a person is about to ask while using their computer. Activity mode: {mode} ({subject}). "
                  "Typical questions in this mode: {style} {learned}\n"
                  "From the visible screen text and recent context, guess the 1-3 questions they are most likely about to ask, "
                  "most likely first. Make them specific to what is on screen (quote the exact term, step, error, field or "
                  "button). If the mode is unknown, start from 'what am I trying to do here'. Return ONLY JSON: "
                  '{{"goal": str, "questions": [{{"text": str, "kind": "explain"|"how-to"|"fix"|"next-step"|"check"|"rewrite"|"compare"|"where", '
                  '"anchor": str (short exact text from the screen this question is about, or "")}}]}}')

GENERIC_Q = {"study": "Can you give me a hint for the next step here?", "coding": "Why isn't this working?",
             "writing": "How can I make this part clearer?", "design": "How do I do this in {app}?",
             "spreadsheets": "What formula do I need here?", "email": "What should I reply?",
             "research": "What's the key point of this page?", "shopping": "Which option is the best value?",
             "admin": "What do I need to do on this screen?", "video": "How do I do this in {app}?",
             "meetings": "What did I miss?", "unknown": "What am I trying to do here, and what's the next step?"}

SIG_KEYS = ("dwell_s", "scroll_reversals", "rereads", "search_switches", "idle_s", "present", "typing_cpm", "time_on_task_s")

def numeric_sig(sig):
    out = {}
    for k in SIG_KEYS:
        try:
            out[k] = bool(sig[k]) if k == "present" else float(sig[k])
        except (KeyError, TypeError, ValueError):
            pass
    return out

def anticipate(cfg, sig):
    """Two-phase: call with behavioural signals only; if likely stuck, reply need_text and the companion calls
    again with screen_text (Accessibility, else OCR) or a screenshot for a vision model."""
    if not cfg.get("companion_enabled", True):
        return {"stuck": False, "gated": "disabled"}
    app, title = str(sig.get("app") or ""), str(sig.get("window_title") or "")
    if blocked(cfg, " ".join([app, title, str(sig.get("url") or "")])):
        return {"stuck": False, "gated": "blocked"}
    now = time.time()
    db = comp_load()
    for pid, pnd in list(db["pending"].items()):  # unanswered guesses older than 5 min count as ignored
        if now - pnd["ts"] > 300 and not pnd.get("done"):
            record_event(db, pnd, "ignored", None, None)
            pnd["done"] = True
    mode, scores = detect_mode(cfg, sig)
    subject = detect_subject(mode, sig)
    score, reasons = stuck_score(cfg, sig, mode)
    th = mode_threshold(cfg, db, mode)
    wkey = f"{app}|{title}"[:200]
    base = {"mode": mode, "subject": subject, "score": score, "threshold": round(th, 3), "reasons": reasons,
            "answer_mode": answer_mode_for(cfg, mode), "pointer": MODES[mode]["pointer"]}
    if not sig.get("force"):
        if score < th:
            comp_save(db)
            return dict(base, stuck=False)
        last = db["last_by_window"].get(wkey, 0)
        if now - last < cfg.get("companion_cooldown_seconds", 240):
            comp_save(db)
            return dict(base, stuck=True, gated="cooldown")
    text = str(sig.get("screen_text") or "").strip()
    img = sig.get("image_b64")
    if not text and not img:
        comp_save(db)
        return dict(base, stuck=True, need_text=True, ocr_allowed=bool(cfg.get("companion_ocr", True)))
    if blocked(cfg, text):
        return dict(base, stuck=False, gated="blocked")
    shots = few_shots(db, mode, app)
    learned = style_summary(db, mode)
    ctx = [f"App: {app}. Window: {title}. URL: {sig.get('url') or '-'}",
           "Signals: " + ("; ".join(reasons) or "user asked"),
           "Recent activity: " + "; ".join(c.get("title", "") for c in recent_cards(5))]
    if shots:
        ctx.append("Questions this user actually asked in similar situations (match their style):\n" +
                   "\n".join(f"- screen: \"{e.get('snippet', '')[:140]}\" → asked: \"{e['final']}\"" for e in shots))
    ctx.append("VISIBLE SCREEN TEXT:\n" + (text[:6000] or "(none; see image)"))
    sys_p = prompt_text("anticipate_sys", ANTICIPATE_SYS).format(mode=mode, subject=subject or app or "general", style=MODES[mode]["style"], learned=learned)
    use_vision = bool(img) and len(text) < 40
    out, err = ollama_chat(cfg, sys_p, "\n\n".join(ctx), images=[img] if use_vision else None,
                           model=cfg.get("vision_model") if use_vision else None)
    data = parse_json(out) if not err else None
    qs = []
    if isinstance(data, dict):
        for q in (data.get("questions") or [])[:3]:
            if isinstance(q, dict) and str(q.get("text") or "").strip():
                anc = str(q.get("anchor") or "").strip()
                if anc and anc.lower() not in text.lower():
                    anc = ""  # only point at things that are really on screen
                qs.append({"text": str(q["text"]).strip()[:200], "kind": str(q.get("kind") or "explain"), "anchor": anc[:120]})
    fallback = not qs
    if fallback:
        qs = [{"text": GENERIC_Q[mode].format(app=app or "this app"), "kind": "next-step", "anchor": ""}]
    aid = secrets.token_hex(6)
    pend = {"id": aid, "ts": now, "mode": mode, "subject": subject, "app": app, "title": title[:200],
            "questions": [q["text"] for q in qs], "snippet": text[:300], "screen": text[:6000],
            "score": score, "threshold": round(th, 3), "fallback": fallback, "vision": use_vision,
            "sig": numeric_sig(sig),
            "error_visible": bool(ERROR_RE.search(text + " " + title))}
    db["pending"][aid] = pend
    db["last_by_window"][wkey] = now
    comp_save(db)
    return dict(base, stuck=True, id=aid, goal=(data or {}).get("goal", "") if isinstance(data, dict) else "",
                questions=qs, best=qs[0]["text"], fallback=fallback, model_error=err)

def answer_mode_for(cfg, mode):
    m = cfg.get("companion_hint_mode", "auto")
    if m == "hints":
        return "hints"
    if m == "direct":
        return "direct" if MODES[mode]["answer"] == "hints" else MODES[mode]["answer"]
    return MODES[mode]["answer"]

ANSWER_STYLE = {
    "hints": {1: "Give ONE short Socratic nudge (a question or pointer to the relevant idea). Do NOT solve anything.",
              2: "Give the next concrete step only, building on the previous hints. Do NOT give the final answer.",
              3: "Now give the full worked solution, step by step, then a one-line takeaway."},
    "fix": "Say in 1-2 sentences what's wrong and why, then give the minimal fix in one fenced code block. No lecture.",
    "rewrite": "Give an improved version in a fenced block (keep their voice), then one line on what changed.",
    "formula": "Give the exact formula in a fenced block using their cell references, then explain each part in one short line.",
    "steps": "Give short numbered steps naming the exact buttons/menus visible on screen.",
    "direct": "Answer directly and concisely (max ~120 words), specific to what's on screen.",
}

def openai_stream(cfg, system, user, images=None, model=None):
    body = json.dumps({"model": model or cfg["model"], "stream": True, "temperature": 0.3,
                       "messages": openai_messages(system, user, images)}).encode()
    req = urllib.request.Request(llm_base(cfg) + "/chat/completions", data=body, headers={"Content-Type": "application/json"})
    in_think = False
    with urllib.request.urlopen(req, timeout=cfg["request_timeout_s"]) as r:
        for line in r:
            line = line.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            piece = ((json.loads(data).get("choices") or [{}])[0].get("delta") or {}).get("content") or ""
            if "<think>" in piece:
                in_think = True
            if in_think:  # drop inline reasoning some models emit
                if "</think>" in piece:
                    in_think, piece = False, piece.split("</think>", 1)[1]
                else:
                    continue
            if piece:
                yield piece

def ollama_stream(cfg, system, user, images=None, model=None):
    if is_cli(cfg) and not images:
        out, err = cli_chat(cfg, system, user)
        if not err:
            yield out
            return
        cfg = dict(cfg, llm_backend="ollama")
    if is_openai(cfg):
        yield from openai_stream(cfg, system, user, images, model)
        return
    url = cfg["ollama_url"].rstrip("/") + "/api/chat"
    um = {"role": "user", "content": user}
    if images:
        um["images"] = images
    body = json.dumps({"model": model or cfg["model"], "stream": True, "think": False, "options": {"temperature": 0.3},
                       "messages": [{"role": "system", "content": system}, um]}).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=cfg["request_timeout_s"]) as r:
        for line in r:
            if not line.strip():
                continue
            j = json.loads(line)
            piece = (j.get("message") or {}).get("content", "")
            if piece:
                yield piece
            if j.get("done"):
                break

def answer_stream(cfg, body):
    """Yields {"delta"}…, optionally {"anchor"}, then {"done"}. Hints mode climbs a ladder: level 1 nudge → 2 next step → 3 full solution."""
    db = comp_load()
    pend = db["pending"].get(str(body.get("id") or ""), {})
    mode = pend.get("mode") or (body.get("mode") if body.get("mode") in MODES else "unknown")
    amode = body.get("answer_mode") or answer_mode_for(cfg, mode)
    if amode not in ANSWER_STYLE:
        amode = "direct"
    level = max(1, min(3, int(body.get("level") or 1)))
    q = str(body.get("question") or "").strip()[:500]
    if not q:
        yield {"error": "empty question"}; return
    screen = pend.get("screen") or str(body.get("screen_text") or "")[:6000]
    style = ANSWER_STYLE[amode][level] if amode == "hints" else ANSWER_STYLE[amode]
    pointer = MODES[mode]["pointer"]
    sys_p = (f"You are a calm, expert on-screen assistant. Activity mode: {mode}. {style} Use only what's on screen and "
             "general knowledge; if something isn't visible, say what you'd need. Plain text, short paragraphs."
             + (" If one specific on-screen element is the place to look or click, end with a final line exactly "
                "'ANCHOR: <its exact visible text>'." if pointer else ""))
    prev = [str(x)[:800] for x in (body.get("previous") or [])][:3]
    user = (f"Question: {q}\n" + ("Earlier hints already given:\n" + "\n".join(f"- {p}" for p in prev) + "\n" if prev else "")
            + f"\nVISIBLE SCREEN TEXT:\n{screen or '(not available)'}")
    yield {"start": True, "mode": mode, "answer_mode": amode, "level": level}
    buf, tail = "", ""
    try:
        for piece in ollama_stream(cfg, sys_p, user):
            buf += piece
            # hold back a possible trailing ANCHOR line so it is not shown as text
            if "ANCHOR:" in buf:
                head, _, tail = buf.partition("ANCHOR:")
                if head:
                    yield {"delta": head}
                buf = "ANCHOR:" + tail
                continue
            safe = buf[:-8] if len(buf) > 8 else ""
            if safe:
                yield {"delta": safe}
                buf = buf[len(safe):]
    except Exception as e:
        yield {"error": f"local model unavailable: {e}"}
        return
    anchor = ""
    if buf.startswith("ANCHOR:"):
        anchor = buf[len("ANCHOR:"):].strip().strip("'\"").splitlines()[0][:120] if buf[7:].strip() else ""
    elif buf:
        yield {"delta": buf}
    if anchor and screen and anchor.lower() in screen.lower():
        yield {"anchor": anchor}
    if pend:
        pend.setdefault("levels", []).append(level)
        db["pending"][pend["id"]] = pend
        comp_save(db)
    yield {"done": True, "level": level, "more": amode == "hints" and level < 3}

def record_event(db, pend, outcome, idx, final):
    preds = pend.get("questions", [])
    pred = preds[idx] if isinstance(idx, int) and 0 <= idx < len(preds) else (preds[0] if preds else "")
    ratio = difflib.SequenceMatcher(None, pred.lower(), (final or "").lower()).ratio() if final else (1.0 if outcome == "chosen" else 0.0)
    hit = outcome == "chosen" or (outcome == "edited" and ratio >= 0.6)
    diff = ""
    if final and outcome in ("edited", "typed") and pred:
        a, b_ = pred.split(), final.split()
        diff = " ".join(("-" + t if op == "-" else "+" + t) for op, t in
                        ((d[0], d[2:]) for d in difflib.ndiff(a, b_)) if op in "+-")[:400]
    db["events"].append({"ts": int(time.time()), "id": pend.get("id"), "mode": pend.get("mode", "unknown"), "app": pend.get("app", ""),
                         "subject": pend.get("subject", ""), "predicted": preds, "chosen_index": idx, "final": final or (pred if outcome == "chosen" else ""),
                         "outcome": outcome, "ratio": round(ratio, 2), "hit": hit, "diff": diff, "snippet": pend.get("snippet", "")[:200],
                         "levels": pend.get("levels", []), "fallback": pend.get("fallback", False),
                         "score": pend.get("score"), "threshold": pend.get("threshold"), "sig": pend.get("sig"),
                         "error_visible": pend.get("error_visible", False), "title": pend.get("title", "")[:120]})
    telemetry("companion", outcome=outcome, mode=pend.get("mode", "unknown"), hit=hit, score=pend.get("score"))

def companion_feedback(cfg, body):
    db = comp_load()
    pend = db["pending"].get(str(body.get("id") or ""))
    if not pend or pend.get("done"):
        return {"error": "unknown or already-rated anticipation"}
    outcome = str(body.get("outcome") or "")
    if outcome not in ("chosen", "edited", "typed", "ignored", "dismissed"):
        return {"error": "outcome must be chosen|edited|typed|ignored|dismissed"}
    idx = body.get("index")
    idx = int(idx) if isinstance(idx, (int, float)) or (isinstance(idx, str) and idx.isdigit()) else None
    final = str(body.get("final_text") or "").strip()[:300] or None
    if outcome == "chosen" and final and idx is not None and final != pend["questions"][idx]:
        outcome = "edited"
    record_event(db, pend, outcome, idx, final)
    pend["done"] = True
    comp_save(db)
    e = db["events"][-1]
    return {"ok": True, "hit": e["hit"], "ratio": e["ratio"], "diff": e["diff"]}

def companion_stats(cfg, now=None):
    now = now or time.time()
    db = comp_load()
    ev = db["events"]
    wk = [e for e in ev if e["ts"] >= now - 7 * 86400]
    rate = lambda es: round(100 * sum(e["hit"] for e in es) / len(es)) if es else None
    def by(key):
        g = {}
        for e in wk:
            g.setdefault(e[key] or "?", []).append(e)
        return {k: {"n": len(v), "hit_rate": rate(v)} for k, v in sorted(g.items(), key=lambda kv: -len(kv[1]))}
    days = []
    for i in range(6, -1, -1):
        d0 = dt.datetime.combine(dt.date.fromtimestamp(now) - dt.timedelta(days=i), dt.time()).timestamp()
        des = [e for e in ev if d0 <= e["ts"] < d0 + 86400]
        days.append({"day": dt.date.fromtimestamp(d0).isoformat(), "n": len(des), "hit_rate": rate(des)})
    sessions, cur = [], None
    for e in sorted((e for e in ev if e["mode"] == "study"), key=lambda e: e["ts"]):
        if cur and e["ts"] - cur["end"] < 1800 and e.get("subject") == cur["subject"]:
            cur["end"] = e["ts"]; cur["questions"] += 1; cur["hints"] += len(e.get("levels") or []); cur["hits"] += e["hit"]
        else:
            cur = {"start": e["ts"], "end": e["ts"], "subject": e.get("subject") or e.get("app"), "app": e.get("app"),
                   "questions": 1, "hints": len(e.get("levels") or []), "hits": int(e["hit"])}
            sessions.append(cur)
    outcomes = {o: sum(1 for e in wk if e["outcome"] == o) for o in ("chosen", "edited", "typed", "ignored", "dismissed")}
    return {"hit_rate_week": rate(wk), "n_week": len(wk), "outcomes": outcomes, "by_mode": by("mode"), "by_app": by("app"),
            "days": days, "history": list(reversed(ev[-40:])), "study_sessions": list(reversed(sessions[-10:])),
            "styles": {m: style_summary(db, m) for m in MODES if style_summary(db, m)},
            "settings": {k: cfg.get(k) for k in ("companion_enabled", "companion_sensitivity", "companion_hint_mode",
                                                   "companion_study_detection", "companion_ocr", "vision_model")}}


def ext_get(cfg, path, qs):
    if path == "/api/doctor":
        return doctor(cfg)
    if path == "/api/memory":
        return memory_overview(cfg)
    if path == "/api/improve":
        import improve
        return improve.overview(cfg)
    if path == "/api/automations":
        return {"items": automations_list()}
    if path == "/api/next-move":
        db = jload(NM_DB, {})
        last = db.get("last")
        if last and time.time() - last["created"] < cfg.get("nextmove_interval_minutes", 4) * 60:
            return last
        return predict_next(cfg, qs.get("trigger", "tick"), qs.get("app"))
    if path == "/api/companion":
        return companion_stats(cfg)
    if path == "/api/next-move/stats":
        db = jload(NM_DB, {})
        return {"stats": db.get("stats", {}), "history": db.get("history", [])[-30:], "dismiss_streak": db.get("dismiss_streak", 0)}
    return None

def brief_feedback(rating, note=""):
    if rating not in ("up", "down"):
        raise ValueError("rating must be up or down")
    telemetry("briefing", rating=rating, has_note=bool(note))
    st = load_state(); st["last_brief_rating"] = rating; save_state(st)
    return {"ok": True}

def ext_post(cfg, path, body):
    if path == "/api/brief/feedback":
        return brief_feedback(str(body.get("rating")), str(body.get("note", ""))[:300])
    if path.startswith("/api/improve/"):
        import improve
        if path == "/api/improve/decide":
            return improve.decide(cfg, str(body["id"]), str(body["decision"]))
        if path == "/api/improve/run":
            return improve.run_async(cfg)
    if path == "/api/memory/trace":
        return fact_trace(str(body["id"]))
    if path == "/api/memory/forget":
        return forget_fact(cfg, str(body["id"]), body.get("confirm") is True)
    if path == "/api/memory/correct":
        txt = str(body["text"]).strip()[:500]
        if not txt:
            raise ValueError("empty correction")
        return forget_fact(cfg, str(body["id"]), body.get("confirm") is True, replacement=txt)
    if path == "/api/memory/resolve":
        return resolve_conflict(cfg, str(body["id"]), str(body["choice"]))
    if path == "/api/memory/confirm":
        return confirm_fact(cfg, str(body["id"]))
    if path == "/api/things/sync":
        return things_sync(cfg, force=True)
    if path == "/api/automations/refresh":
        return {"items": automations_refresh(cfg)}
    if path == "/api/automations/draft":
        return automation_draft(cfg, str(body["id"]), str(body.get("hint", ""))[:300])
    if path == "/api/automations/dryrun":
        return automation_dryrun(cfg, str(body["id"]))
    if path == "/api/automations/decide":
        return automation_decide(str(body["id"]), str(body["decision"]))
    if path == "/api/automations/run":
        return automation_run(cfg, str(body["id"]), body.get("confirm") is True)
    if path == "/api/next-move":
        return predict_next(cfg, str(body.get("trigger", "tick")), body.get("app"), bool(body.get("force")))
    if path == "/api/anticipate":
        job_status("companion", True, detail="orb checked in", throttle=60)
        return anticipate(cfg, body)
    if path == "/api/companion/feedback":
        return companion_feedback(cfg, body)
    if path == "/api/next-move/feedback":
        return nm_feedback(cfg, str(body["id"]), str(body.get("outcome")), body.get("action"))
    return None


def set_home(path):
    """Point every path at another home folder (used by tests and BRIEFING_HOME)."""
    global HOME, CONFIG_PATH, MEM, INBOX, INDEX_DB, LOG_DIR, STATE_PATH, ERR_LOG, TODOS, DATA, AUTO_DIR, AUTO_DB, NM_DB
    HOME = Path(path)
    CONFIG_PATH, MEM, LOG_DIR = HOME / "config.json", HOME / "memory", HOME / "log"
    STATE_PATH, ERR_LOG, AUTO_DIR = HOME / "state.json", HOME / "briefing.log", HOME / "automations"
    INBOX, INDEX_DB, TODOS, DATA = MEM / "inbox.jsonl", MEM / "index.sqlite", MEM / "todos.json", MEM / "data"
    global COMP_DB
    AUTO_DB, NM_DB, COMP_DB = DATA / "automations.json", DATA / "nextmove.json", DATA / "companion.json"

# ---------------------------------------------------------------- CLI

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["wake", "checkin", "distill", "nightly", "weekly", "ask", "cleanup", "reindex",
                                        "brief", "status", "debrief", "coach", "report", "forget", "context", "serve",
                                        "resume", "todo", "automations", "draft", "dryrun", "approve", "reject",
                                        "run-automation", "next-move", "next-feedback", "improve", "proposals",
                                        "improve-decide", "feedback", "telemetry", "things-sync", "vault",
                                        "memory", "memory-trace", "memory-forget", "memory-correct", "resolve", "doctor"])
    ap.add_argument("question", nargs="*")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--from", dest="frm")
    ap.add_argument("--to")
    ap.add_argument("--rebuild", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--yes", action="store_true", help="explicit approval for run-automation")
    ap.add_argument("--app", default=None)
    a = ap.parse_args(argv)
    os.umask(0o077)
    cfg = load_config()
    mem_init()
    if not TODOS.exists():
        todos_save([])
    q = " ".join(a.question)
    cmds = {"wake": lambda: cmd_wake(cfg), "checkin": lambda: cmd_checkin(cfg),
            "distill": lambda: cmd_distill(cfg), "nightly": lambda: cmd_nightly(cfg),
            "weekly": lambda: cmd_weekly(cfg), "ask": lambda: cmd_ask(cfg, q),
            "cleanup": lambda: cmd_cleanup(cfg), "reindex": lambda: "indexed %d chunks (fts5=%s)" % reindex(cfg),
            "brief": lambda: cmd_brief(cfg, force=a.force), "status": lambda: cmd_status(cfg),
            "debrief": lambda: cmd_debrief(cfg), "coach": lambda: cmd_coach(cfg), "report": lambda: cmd_report(cfg),
            "forget": lambda: cmd_forget(cfg, a.frm, a.to, a.rebuild) if a.frm and a.to else "usage: forget --from DATE --to DATE",
            "context": lambda: json.dumps(context_now(cfg)) if a.json else context_now(cfg)["text"],
            "automations": lambda: "\n".join(f"{a['id']} [{a.get('status')}] {a['minutes_saved_week']:>5} min/wk  {a['label']}"
                                              for a in automations_refresh(cfg)) or "no repeated patterns yet",
            "draft": lambda: json.dumps(automation_draft(cfg, q), indent=1),
            "dryrun": lambda: json.dumps(automation_dryrun(cfg, q), indent=1),
            "approve": lambda: automation_decide(q, "approve").get("status", "error"),
            "reject": lambda: automation_decide(q, "reject").get("status", "error"),
            "run-automation": lambda: json.dumps(automation_run(cfg, q, confirm=a.yes)),
            "next-move": lambda: json.dumps(predict_next(cfg, "cli", a.app, a.force), indent=1),
            "next-feedback": lambda: json.dumps(nm_feedback(cfg, a.question[0], a.question[1],
                                                             int(a.question[2]) if len(a.question) > 2 else None)),
            "improve": lambda: json.dumps(__import__("improve").run(cfg, force=a.force), indent=1),
            "proposals": lambda: json.dumps(__import__("improve").overview(cfg)["proposals"], indent=1),
            "improve-decide": lambda: json.dumps(__import__("improve").decide(cfg, a.question[0], a.question[1])),
            "feedback": lambda: json.dumps(brief_feedback(a.question[0] if a.question else "", " ".join(a.question[1:]))),
            "telemetry": lambda: json.dumps(__import__("improve").metrics(cfg), indent=1),
            "things-sync": lambda: json.dumps(things_sync(cfg, force=True)),
            "vault": lambda: vault_sync(cfg),
            "doctor": lambda: json.dumps(doctor(cfg), indent=1) if a.json else doctor_text(cfg),
            "memory": lambda: json.dumps(memory_overview(cfg)["counts"]) + "\n" + "\n".join(
                f"{f['id']} [{f['clock']}/{f['status']}] {fact_line(f)[2:]}" for f in memory_overview(cfg)["facts"][:50]),
            "memory-trace": lambda: json.dumps(fact_trace(q), indent=1),
            "memory-forget": lambda: json.dumps(forget_fact(cfg, q, confirm=a.yes), indent=1),
            "memory-correct": lambda: json.dumps(forget_fact(cfg, a.question[0], confirm=a.yes, replacement=" ".join(a.question[1:])), indent=1),
            "resolve": lambda: json.dumps(resolve_conflict(cfg, a.question[0], a.question[1])),
            "serve": lambda: cmd_serve(cfg), "resume": lambda: offer_resume(cfg),
            "todo": lambda: ("added" if todo_add(q, "cli") else "duplicate") if q else
                    "\n".join(f"[{'x' if t['done'] else ' '}] {t['id']} {t['text']}" for t in todos_load())}
    tracked = {"wake": "wake", "distill": "distill", "nightly": "nightly", "improve": "improve", "cleanup": "cleanup"}
    JOB_ERRORS.clear()
    try:
        r = cmds[a.command]()
        if a.command in tracked:
            job_status(tracked[a.command], not JOB_ERRORS, detail=str(r)[:200], error="; ".join(dict.fromkeys(JOB_ERRORS))[:300])
        if a.command == "nightly":
            harden_perms()
        if r:
            print(r)
        if a.command in tracked and JOB_ERRORS:
            sys.exit(1)
    except Exception as e:
        if a.command in tracked:
            job_status(tracked[a.command], False, error=f"{type(e).__name__}: {e}")
        telemetry("error", where=a.command, error=type(e).__name__)
        log(f"{a.command} crashed: {e!r}")
        raise

if __name__ == "__main__":
    main()
