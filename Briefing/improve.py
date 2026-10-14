"""Conservative self-improvement loop for Dayflow Briefing (local only, keyless).

Nightly (`briefing.py improve`, LaunchAgent 02:30, skipped on battery or low disk):
  1. metrics from local telemetry + your own logged outcomes; pick the top 1-2 problems
  2. candidates, cheapest first: parameter tuning (offline replay / grid search on your history),
     prompt variants (replayed on held-out past cases), optionally a small code patch from a local coding model
  3. gate: each candidate lives on its own git branch of the app dir and must pass the full test suite AND beat the
     baseline on held-out replay by more than the noise threshold, with no regressions (hits kept, latency, errors)
  4. winners become proposals; nothing changes until you approve (auto-apply exists for param-only changes, off by default)
Approve = git merge + backup bundle + dashboard restart; Reject = delete branch; Undo = git revert of an approved merge.
Never touches ~/Briefing/memory (reads it only), never edits privacy/approval code (file + function allowlist).

Working rules (ideas borrowed from obra/superpowers' TDD / debugging / verification skills; nothing vendored):
  * root cause before patching: every candidate carries a diagnosis computed from your data; no diagnosis, no candidate
  * failing test first: each candidate states a check that FAILS on the current build and must PASS with the change
    (code patches must add a new test under tests/improve_cases/ that fails before the fix and passes after)
  * verify before "ready": full test suite + held-out replay must both pass before a proposal is shown to you
  * smallest diff wins (idea from DietrichGebert/ponytail): deletions and simplifications rank above additions, code
    growth beyond `improve_max_net_growth` lines is rejected, and a patch may never remove validation, error handling,
    privacy/redaction or tests
  * the loop never writes memories: ~/Briefing/memory is hashed before/after each run and any change aborts the run
"""
import ast, difflib, json, math, os, re, secrets, shutil, subprocess, sys, tempfile, threading, time
from pathlib import Path
import briefing as b

# ---------------------------------------------------------------- safety rails (this file itself is never patchable)
PROTECTED_FILES = {"improve.py", "install.sh", "uninstall.sh", "Companion.swift"}
PROTECTED_DIRS = ("tests/",)
PROTECTED_FUNCS = {  # privacy, approval, deletion, network surface, and the loop's own plumbing
    "blocked", "anticipate", "numeric_sig", "automation_decide", "automation_run", "automation_dryrun", "lint_script",
    "automation_draft", "perform_action", "nm_validate", "do_resume", "offer_resume", "resume_targets", "cmd_forget",
    "cmd_cleanup", "deletable_recordings", "make_handler", "set_home", "load_config", "load_overrides", "prompt_text",
    "telemetry", "telemetry_read", "safe_write", "backup", "push", "ext_get", "ext_post", "main", "things_sync", "cli_chat", "cli_bin",
    "things_add_url", "things_update_url", "things_open", "vault_sync", "record_whisper", "companion_feedback", "record_event",
    "ingest_facts", "forget_fact", "resolve_conflict", "confirm_fact", "recheck_facts", "facts_for_use", "strip_untrusted",
    "scrub_personal", "record_use", "fact_trace", "curate", "merge_file", "add_daily", "todo_add", "build_context"}
TEST_CASES_DIR = "tests/improve_cases/"
# removing any of these is "cutting a safety net": always rejected, however small the diff
SAFETY_NET_RE = re.compile(r"\b(raise|except|try:|assert|redact|blocked|blocklist|validate|valid_|ValueError|KeyError|TypeError|"
                           r"confirm|approve|scrub_personal|strip_untrusted|telemetry|log\(|if not\b|isinstance|min\(|max\()")
FORBIDDEN_TOKENS = ("subprocess", "os.system", "eval(", "exec(", "urlopen", "socket", "blocked", "blocklist", "confirm",
                    "approve", "unlink", "rmtree", "shutil", "open(", "__import__", "MEM", "HOME", "CONFIG_PATH",
                    "ingest_facts", "merge_file", "add_daily", "todo_add", "curate(", "facts.json", "write_text")
# hard bounds for tunables, whatever the replay says
BOUNDS = {"companion_threshold_base": (0.55, 0.95), "companion_ignore_backoff": (0.0, 0.3),
          "companion_cooldown_seconds": (60, 1800), "nextmove_min_confidence": (0.4, 0.9), "embed_min_similarity": (0.3, 0.8)}
IGN = ("ignored", "dismissed")
WEEK = 7 * 86400

def idir():
    d = b.HOME / "improve"
    d.mkdir(parents=True, exist_ok=True)
    return d

def repo_dir(cfg):
    return Path(cfg.get("improve_repo") or b.APP_DIR).resolve()

def props_load():
    return b.jload(idir() / "proposals.json", [])

def props_save(p):
    b.jsave(idir() / "proposals.json", p[-100:])

def runlog(entry):
    with open(idir() / "runs.jsonl", "a") as f:
        f.write(json.dumps(dict({"ts": int(time.time())}, **entry)) + "\n")

def runs_load(n=20):
    p = idir() / "runs.jsonl"
    return [json.loads(x) for x in p.read_text().splitlines()[-n:]] if p.exists() else []

# ---------------------------------------------------------------- Evolution Engine state machine & modes
STATES = (
    "IDLE", "OBSERVING", "ANALYZING", "PROPOSING", "REVIEWING", "APPROVAL_PENDING",
    "BASELINING", "IMPLEMENTING", "VERIFYING", "EVALUATING", "READY_FOR_REVIEW",
    "MERGED", "REJECTED", "REVERTED", "RECORDED",
    "CANCELLED", "BLOCKED", "FAILED", "BUDGET_EXCEEDED",
)
MODES = {
    "audit": {"level": "L0", "label": "Audit (L0: Observe only)", "allow_branch": False, "allow_auto_merge": False},
    "guided": {"level": "L0-L1", "label": "Guided (L0-L1: Propose for approval)", "allow_branch": True, "allow_auto_merge": False},
    "controlled_autonomous": {"level": "Delegated L2", "label": "Controlled autonomous (L2: Scoped param auto-apply)", "allow_branch": True, "allow_auto_merge": True},
    "scheduled": {"level": "L0 / Delegated L2", "label": "Scheduled (Nightly bounded check)", "allow_branch": True, "allow_auto_merge": False},
}

def current_mode(cfg, override=None):
    if override and override in MODES:
        return override
    m = str(cfg.get("improve_mode") or "").strip()
    if m in MODES:
        return m
    return "controlled_autonomous" if cfg.get("improve_auto_apply_params") else "guided"

def state_load():
    return b.jload(idir() / "state.json", {"state": "IDLE", "op_id": "", "mode": "guided", "updated": 0, "reason": "ready"})

def transition(to_state, op_id="", actor="engine", reason="", input_refs=None, output_refs=None, mode=None):
    cur = state_load()
    from_state = cur.get("state") or "IDLE"
    now = round(time.time(), 3)
    entry = {
        "ts": int(now),
        "ts_ms": int(now * 1000),
        "op_id": op_id or cur.get("op_id") or time.strftime("%Y%m%d-%H%M%S"),
        "from_state": from_state,
        "to_state": to_state,
        "actor": actor,
        "mode": mode or cur.get("mode") or "guided",
        "reason": reason,
        "input_refs": list(input_refs or []),
        "output_refs": list(output_refs or []),
    }
    b.jsave(idir() / "state.json", {
        "state": to_state,
        "from_state": from_state,
        "op_id": entry["op_id"],
        "mode": entry["mode"],
        "updated": int(now),
        "reason": reason,
    })
    try:
        with open(idir() / "transitions.jsonl", "a") as f:
            f.write(json.dumps(entry) + "\n")
    except Exception:
        pass
    return entry

def transitions_load(n=25):
    p = idir() / "transitions.jsonl"
    if not p.exists():
        return []
    out = []
    for line in p.read_text().splitlines()[-n:]:
        try:
            out.append(json.loads(line))
        except ValueError:
            continue
    return out

def priority_score(expected_user_value, evidence_confidence, urgency, estimated_effort=1.0, risk_multiplier=1.0):
    """Transparent triage heuristic: (value * confidence * urgency) / (effort * risk)."""
    denom = max(0.1, float(estimated_effort) * float(risk_multiplier))
    return round((float(expected_user_value) * float(evidence_confidence) * float(urgency)) / denom, 3)

def index_codebase(cfg):
    repo = repo_dir(cfg)
    py_files = sorted(p.name for p in repo.glob("*.py")) if repo.exists() else []
    test_files = sorted(p.name for p in (repo / "tests").glob("test_*.py")) if (repo / "tests").exists() else []
    return {
        "repo_path": str(repo),
        "git_ready": (repo / ".git").exists(),
        "modules": py_files,
        "test_suites": test_files,
        "protected_files": sorted(PROTECTED_FILES),
        "protected_functions_count": len(PROTECTED_FUNCS),
    }

def is_duplicate_rejected(cand, mode="guided"):
    """Prevent re-proposing a candidate identical to one the user already rejected in the same mode."""
    for p in props_load():
        if p.get("status") != "rejected" or p.get("kind") != cand.get("kind") or p.get("problem") != cand.get("problem"):
            continue
        if (p.get("contract") or {}).get("mode", "guided") != mode:
            continue
        if cand["kind"] == "param" and p.get("change") == cand.get("change"):
            return True
        if cand["kind"] == "prompt" and p.get("prompt") == cand.get("prompt"):
            return True
    return False

def iteration_contract(cfg, mode, problem, cand=None):
    info = MODES.get(mode, MODES["guided"])
    return {
        "objective": (cand or {}).get("summary") or problem.get("text", ""),
        "problem_id": problem.get("id", ""),
        "mode": mode,
        "authority_level": info["level"],
        "risk_rating": "low" if (cand or {}).get("kind") in (None, "param") else ("medium" if (cand or {}).get("kind") == "prompt" else "elevated"),
        "allowed_files": list(cfg.get("improve_code_allowlist", ["briefing.py"])) + ["tunables.json", "prompts.json"],
        "protected_files": sorted(PROTECTED_FILES),
        "budget": {
            "max_diff_lines": cfg.get("improve_max_diff_lines", 60),
            "max_net_growth": cfg.get("improve_max_net_growth", 20),
            "min_free_gb": cfg.get("improve_min_free_gb", 2),
        },
        "rollback": "git revert --no-edit -m 1 <merge_commit> + pre-merge git bundle in ~/Briefing/improve/backups/",
    }

# ---------------------------------------------------------------- metrics + problems
def pct(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(q * len(xs)))] if xs else None

def metrics(cfg, now=None):
    now = now or time.time()
    tel = b.telemetry_read(now - WEEK)
    comp = [e for e in b.comp_load()["events"] if e["ts"] >= now - WEEK]
    nm = [h for h in b.jload(b.NM_DB, {}).get("history", []) if h["ts"] >= now - WEEK]
    llm = [t for t in tel if t["kind"] == "llm"]
    rate = lambda k, xs: round(sum(1 for x in xs if k(x)) / len(xs), 3) if xs else None
    auto = [t for t in tel if t["kind"] == "automation" and t.get("decision") in ("approve", "reject")]
    br = [t for t in tel if t["kind"] == "briefing"]
    nt = [t for t in tel if t["kind"] == "notch"]
    return {
        "notch": {"n": len(nt), "ack_rate": rate(lambda t: bool(t.get("shown")), nt),
                  "fallback_rate": rate(lambda t: not t.get("shown"), nt)},
        "companion": {"n": len(comp), "ignore_rate": rate(lambda e: e["outcome"] in IGN, comp), "hit_rate": rate(lambda e: e["hit"], comp),
                      "miss_rate": rate(lambda e: e["outcome"] in ("edited", "typed") and not e["hit"], comp)},
        "nextmove": {"n": len(nm), "dismiss_rate": rate(lambda h: h["outcome"] != "accept", nm)},
        "llm": {"n": len(llm), "p50_ms": pct([t["ms"] for t in llm], .5), "p90_ms": pct([t["ms"] for t in llm], .9),
                "error_rate": rate(lambda t: not t.get("ok"), llm)},
        "errors": {"n": sum(1 for t in tel if t["kind"] == "error")},
        "automation": {"n": len(auto), "reject_rate": rate(lambda t: t["decision"] == "reject", auto)},
        "briefing": {"n": len(br), "down_rate": rate(lambda t: t.get("rating") == "down", br)},
    }

def problems(cfg, m):
    """Ranked list; 'fixable' ones have a candidate generator, others are only reported."""
    ms, out = cfg.get("improve_min_samples", 30), []
    c, n, l = m["companion"], m["nextmove"], m["llm"]
    nt = m.get("notch") or {"n": 0, "fallback_rate": None}
    if c["n"] >= ms and (c["ignore_rate"] or 0) > 0.35:
        conf = min(1.0, round(c["n"] / max(ms, 60), 2))
        out.append({"id": "companion_interrupts", "severity": c["ignore_rate"], "fixable": True,
                    "confidence": conf, "effort": 1.0, "risk": 1.0,
                    "priority": priority_score(c["ignore_rate"], conf, 1.2, 1.0, 1.0),
                    "text": f"{round(c['ignore_rate'] * 100)}% of companion guesses were ignored"})
    if c["n"] >= ms and (c["miss_rate"] or 0) > 0.2:
        conf = min(1.0, round(c["n"] / max(ms, 60), 2))
        out.append({"id": "companion_misses", "severity": c["miss_rate"], "fixable": True,
                    "confidence": conf, "effort": 1.2, "risk": 1.1,
                    "priority": priority_score(c["miss_rate"], conf, 1.1, 1.2, 1.1),
                    "text": f"{round(c['miss_rate'] * 100)}% of the time you asked something different from the guesses"})
    if n["n"] >= ms and (n["dismiss_rate"] or 0) > 0.5:
        conf = min(1.0, round(n["n"] / max(ms, 60), 2))
        out.append({"id": "nextmove_dismissed", "severity": n["dismiss_rate"], "fixable": True,
                    "confidence": conf, "effort": 1.0, "risk": 1.0,
                    "priority": priority_score(n["dismiss_rate"], conf, 1.1, 1.0, 1.0),
                    "text": f"{round(n['dismiss_rate'] * 100)}% of next-move suggestions were dismissed"})
    if l["n"] >= ms and (l["error_rate"] or 0) > 0.1:
        conf = min(1.0, round(l["n"] / max(ms, 60), 2))
        out.append({"id": "llm_errors", "severity": l["error_rate"], "fixable": False,
                    "confidence": conf, "effort": 1.5, "risk": 1.0,
                    "priority": priority_score(l["error_rate"], conf, 1.4, 1.5, 1.0),
                    "text": f"{round(l['error_rate'] * 100)}% of local model calls failed (is Ollama running / model pulled?)"})
    if m["briefing"]["n"] >= 5 and (m["briefing"]["down_rate"] or 0) > 0.4:
        conf = min(1.0, round(m["briefing"]["n"] / 10, 2))
        out.append({"id": "briefing_disliked", "severity": m["briefing"]["down_rate"], "fixable": False,
                    "confidence": conf, "effort": 1.5, "risk": 1.2,
                    "priority": priority_score(m["briefing"]["down_rate"], conf, 1.2, 1.5, 1.2),
                    "text": "most briefings got a thumbs-down (not enough labelled examples to tune automatically yet)"})
    if nt["n"] >= 5 and (nt["fallback_rate"] or 0) > 0.5:
        conf = min(1.0, round(nt["n"] / 10, 2))
        out.append({"id": "notch_fallback_high", "severity": nt["fallback_rate"], "fixable": False,
                    "confidence": conf, "effort": 1.0, "risk": 1.0,
                    "priority": priority_score(nt["fallback_rate"], conf, 1.0, 1.0, 1.0),
                    "text": f"{round(nt['fallback_rate'] * 100)}% of Briefing notices fell back to macOS dialogs (is Dayframe open with Notch Island enabled?)"})
    return sorted(out, key=lambda p: -p["severity"])

# ---------------------------------------------------------------- replay (pure: reads history, writes nothing)
def split(xs, frac=0.7):
    k = int(len(xs) * frac)
    return xs[:k], xs[k:]

def comp_cases():
    return sorted((e for e in b.comp_load()["events"] if isinstance(e.get("sig"), dict) and e.get("mode") in b.MODES),
                  key=lambda e: e["ts"])

def replay_companion(cfg, events, history=None):
    """Would each logged guess still have been shown under cfg? Returns per-event decisions + summary."""
    hist = list(history or [])
    last, keep = {}, []
    for e in events:
        sig = dict(e["sig"], screen_text="error" if e.get("error_visible") else "", window_title="")
        score, _ = b.stuck_score(cfg, sig, e["mode"])
        th = b.mode_threshold(cfg, {"events": hist[-60:]}, e["mode"])
        key = (e.get("app"), e.get("title", ""))
        k = score >= th and e["ts"] - last.get(key, -1e12) >= cfg.get("companion_cooldown_seconds", 240)
        if k:
            last[key] = e["ts"]
        keep.append(k)
        hist.append(e)
    return summarize(events, keep, lambda e: e["hit"], lambda e: e["outcome"] in IGN)

def replay_nextmove(cfg, hist):
    keep = [(h.get("confidence") or 0) >= cfg.get("nextmove_min_confidence", 0.55) for h in hist]
    return summarize(hist, keep, lambda h: h["outcome"] == "accept", lambda h: h["outcome"] != "accept")

def summarize(events, keep, good, bad):
    n = len(events)
    goods = sum(1 for e in events if good(e))
    return {"n": n, "keep": keep, "shown": sum(keep), "good_total": goods,
            "good_kept": sum(1 for e, k in zip(events, keep) if k and good(e)),
            "waste": round(sum(1 for e, k in zip(events, keep) if k and bad(e)) / n, 4) if n else 0,
            "_bad": [1 if (k and bad(e)) else 0 for e, k in zip(events, keep)],
            "_good": [1 if (k and good(e)) else 0 for e, k in zip(events, keep)]}

def paired_gain(base, cand):
    """Mean reduction in wasted interruptions per case, and its standard error (paired)."""
    d = [x - y for x, y in zip(base["_bad"], cand["_bad"])]
    n = len(d)
    if not n:
        return 0.0, 1.0
    mu = sum(d) / n
    var = sum((x - mu) ** 2 for x in d) / max(1, n - 1)
    return mu, math.sqrt(var / n)

def judge(cfg, base, cand, label):
    """The noise gate shared by every candidate kind. Returns (ok, reason, deltas)."""
    gain, se = paired_gain(base, cand)
    need = max(cfg.get("improve_min_gain", 0.05), 2 * se)
    lost = (base["good_kept"] - cand["good_kept"]) / max(1, base["good_kept"])
    deltas = {f"{label}: wasted interruptions": [base["waste"], cand["waste"]],
              f"{label}: useful guesses kept": [base["good_kept"], cand["good_kept"]], "held-out cases": [base["n"], cand["n"]]}
    if base["n"] < 10:
        return False, f"only {base['n']} held-out cases (need 10+)", deltas
    if lost > 0.05:
        return False, f"would lose {round(lost * 100)}% of useful guesses", deltas
    if gain < need:
        return False, f"gain {gain:.3f} below noise threshold {need:.3f}", deltas
    return True, f"gain {gain:.3f} > {need:.3f}", deltas

def grid(cur, steps, key):
    lo, hi = BOUNDS[key]
    vals = sorted({round(min(max(cur + s, lo), hi), 3) for s in steps})
    return vals

def root_cause_companion(events, keep):
    """Which behavioural signal separates guesses you ignored from ones you used? (diagnosis before any fix)"""
    shown = [e for e, k in zip(events, keep) if k]
    ign = [e for e in shown if e["outcome"] in IGN]
    used = [e for e in shown if e["hit"]]
    if not ign:
        return ""
    keys = ("dwell_s", "scroll_reversals", "rereads", "search_switches", "idle_s", "typing_cpm", "time_on_task_s")
    avg = lambda es, k: sum(float(e["sig"].get(k) or 0) for e in es) / max(1, len(es))
    ratios = sorted(((avg(used, k) / max(avg(ign, k), 1e-6), k) for k in keys if avg(ign, k) or avg(used, k)), reverse=True)
    modes = {}
    for e in ign:
        modes[e["mode"]] = modes.get(e["mode"], 0) + 1
    top = max(modes, key=modes.get)
    k = ratios[0][1] if ratios else "dwell_s"
    return (f"{len(ign)} of {len(shown)} shown guesses were ignored, mostly in {top} mode ({modes[top]}). They fired on weaker "
            f"signals: {k.replace('_s', '').replace('_', ' ')} averaged {avg(ign, k):.0f} when ignored vs {avg(used, k):.0f} when the "
            f"guess was used, so the threshold is too low for those moments rather than the guesses being wrong.")

def red_green(label, base_val, cand_val, need):
    """The 'failing test first' check for tuning candidates: it must fail on the current build and pass with the change."""
    target = round(base_val - need, 4)
    return {"check": f"held-out {label} ≤ {target}", "baseline": "fail" if base_val > target else "pass",
            "candidate": "pass" if cand_val <= target else "fail"}

def tune_companion(cfg):
    ev = comp_cases()
    if len(ev) < cfg.get("improve_min_samples", 30):
        return None, f"only {len(ev)} companion cases with signals"
    train, test = split(ev)
    cur = {k: cfg[k] for k in ("companion_threshold_base", "companion_ignore_backoff", "companion_cooldown_seconds")}
    best, best_score = cur, None
    for tb in grid(cur["companion_threshold_base"], [0, .03, .06, .09, .12, .15], "companion_threshold_base"):
        for bo in grid(cur["companion_ignore_backoff"], [0, .04, .08], "companion_ignore_backoff"):
            for cd in grid(cur["companion_cooldown_seconds"], [0, cur["companion_cooldown_seconds"] * .5, cur["companion_cooldown_seconds"]], "companion_cooldown_seconds"):
                c = dict(cfg, companion_threshold_base=tb, companion_ignore_backoff=bo, companion_cooldown_seconds=int(cd))
                r = replay_companion(c, train)
                if r["good_total"] and r["good_kept"] < 0.97 * replay_companion(cfg, train)["good_kept"]:
                    continue
                sc = (r["waste"], -r["good_kept"], abs(tb - cur["companion_threshold_base"]))  # prefer smallest change
                if best_score is None or sc < best_score:
                    best, best_score = {"companion_threshold_base": tb, "companion_ignore_backoff": bo, "companion_cooldown_seconds": int(cd)}, sc
    change = {k: v for k, v in best.items() if v != cur[k]}
    if not change:
        return None, "current settings are already the best on your history"
    base_r = replay_companion(cfg, test, train)
    cand_r = replay_companion(dict(cfg, **change), test, train)
    ok, why, deltas = judge(cfg, base_r, cand_r, "companion")
    rc = root_cause_companion(test, base_r["keep"])
    rg = red_green("wasted interruptions", base_r["waste"], cand_r["waste"], max(cfg.get("improve_min_gain", 0.05), 2 * paired_gain(base_r, cand_r)[1]))
    return {"kind": "param", "problem": "companion_interrupts", "change": change, "before": {k: cur[k] for k in change},
            "ok": ok, "why": why, "deltas": deltas, "root_cause": rc, "test_first": rg,
            "summary": (f"The companion showed guesses you ignored. Changing {fmt_change(cur, change)} would have cut wasted "
                        f"pop-ups from {pc(base_r['waste'])} to {pc(cand_r['waste'])} of {base_r['n']} recent held-out moments, "
                        f"keeping {cand_r['good_kept']} of {base_r['good_kept']} guesses you actually used.")}, why

def tune_nextmove(cfg):
    hist = [h for h in b.jload(b.NM_DB, {}).get("history", []) if h.get("confidence") is not None]
    if len(hist) < cfg.get("improve_min_samples", 30):
        return None, f"only {len(hist)} next-move outcomes with confidence"
    train, test = split(hist)
    cur = cfg.get("nextmove_min_confidence", 0.55)
    base_train = replay_nextmove(cfg, train)
    best, bs = cur, None
    for v in grid(cur, [0, .05, .1, .15, .2], "nextmove_min_confidence"):
        r = replay_nextmove(dict(cfg, nextmove_min_confidence=v), train)
        if r["good_kept"] < 0.97 * base_train["good_kept"]:
            continue
        sc = (r["waste"], abs(v - cur))
        if bs is None or sc < bs:
            best, bs = v, sc
    if best == cur:
        return None, "current next-move confidence bar is already the best on your history"
    base_r, cand_r = replay_nextmove(cfg, test), replay_nextmove(dict(cfg, nextmove_min_confidence=best), test)
    ok, why, deltas = judge(cfg, base_r, cand_r, "next-move")
    acc = sorted(h["confidence"] for h in test if h["outcome"] == "accept")
    dis = sorted(h["confidence"] for h in test if h["outcome"] != "accept")
    rc = (f"Dismissed suggestions had median confidence {dis[len(dis) // 2]:.2f} vs {acc[len(acc) // 2]:.2f} for accepted ones: "
          f"low-confidence guesses are the ones you wave off.") if acc and dis else ""
    rg = red_green("dismissed suggestions", base_r["waste"], cand_r["waste"], max(cfg.get("improve_min_gain", 0.05), 2 * paired_gain(base_r, cand_r)[1]))
    return {"root_cause": rc, "test_first": rg,"kind": "param", "problem": "nextmove_dismissed", "change": {"nextmove_min_confidence": best},
            "before": {"nextmove_min_confidence": cur}, "ok": ok, "why": why, "deltas": deltas,
            "summary": (f"Next-move suggestions were often dismissed. Raising the confidence bar from {cur} to {best} would have "
                        f"cut dismissed suggestions from {pc(base_r['waste'])} to {pc(cand_r['waste'])} on {base_r['n']} held-out "
                        f"cases while keeping {cand_r['good_kept']} of {base_r['good_kept']} you accepted.")}, why

def pc(x):
    return f"{int(x * 100 + 0.5)}%"

def fmt_change(cur, change):
    names = {"companion_threshold_base": "the stuck threshold", "companion_ignore_backoff": "the back-off when ignored",
             "companion_cooldown_seconds": "the cooldown (s)"}
    return ", ".join(f"{names.get(k, k)} {cur[k]} → {v}" for k, v in change.items())

# ---------------------------------------------------------------- prompt variants (replayed on held-out cases)
PROMPT_TWEAKS = [
    " Write each question the way this user types: match the length and opening words of their past questions.",
    " Prefer the single most concrete obstacle on screen; never ask generic questions like 'what is this'.",
]

def valid_prompt(p):
    try:
        p.format(mode="x", subject="y", style="z", learned="")
    except (KeyError, IndexError, ValueError):
        return False
    return '"questions"' in p and len(p) < 4000

def prompt_cases():
    return [e for e in b.comp_load()["events"] if e["outcome"] in ("chosen", "edited", "typed") and e.get("final") and e.get("snippet")]

def ask_model(cfg, system, user):  # seam for tests
    t0 = time.time()
    out, err = b.ollama_chat(cfg, system, user)
    return out, err, (time.time() - t0) * 1000

def replay_prompt(cfg, prompt, cases):
    rows = []
    for e in cases:
        mode = e["mode"] if e["mode"] in b.MODES else "unknown"
        sysp = prompt.format(mode=mode, subject=e.get("subject") or e.get("app") or "general", style=b.MODES[mode]["style"], learned="")
        out, err, ms = ask_model(cfg, sysp, f"App: {e.get('app')}. Window: {e.get('title', '')}.\n\nVISIBLE SCREEN TEXT:\n{e['snippet']}")
        data = b.parse_json(out) if not err else None
        qs = [str(q.get("text", "")) for q in (data or {}).get("questions", []) if isinstance(q, dict)] if isinstance(data, dict) else []
        best = max((difflib.SequenceMatcher(None, q.lower(), e["final"].lower()).ratio() for q in qs), default=0.0)
        rows.append({"hit": best >= 0.6, "ms": ms, "fail": not qs})
    n = len(rows) or 1
    return {"n": len(rows), "hit_rate": round(sum(r["hit"] for r in rows) / n, 4), "ms": round(sum(r["ms"] for r in rows) / n, 1),
            "fails": sum(r["fail"] for r in rows), "_hits": [int(r["hit"]) for r in rows]}

def tune_prompt(cfg):
    cases = prompt_cases()
    if len(cases) < cfg.get("improve_min_prompt_cases", 12):
        return None, f"only {len(cases)} past questions to learn from"
    train, test = split(cases)
    test = test[-40:]
    base_p = b.prompt_text("anticipate_sys", b.ANTICIPATE_SYS)
    variants = [base_p + t for t in PROMPT_TWEAKS if t not in base_p]
    ex = "\n".join(f"- {e['final']}" for e in train[-12:])
    out, err, _ = ask_model(cfg, "You improve system prompts. Return ONLY the improved prompt text.",
                            f"Current prompt:\n{base_p}\n\nReal questions this user asked:\n{ex}\n\nRewrite the prompt so its "
                            "predictions match how this user phrases questions. Keep every {placeholder} and the JSON format exactly.")
    if not err and out and valid_prompt(out.strip()):
        variants.append(out.strip())
    base_r = replay_prompt(cfg, base_p, test)
    best = None
    for v in variants:
        r = replay_prompt(cfg, v, test)
        if best is None or r["hit_rate"] > best[1]["hit_rate"]:
            best = (v, r)
    if not best:
        return None, "no valid prompt variants"
    v, r = best
    d = [y - x for x, y in zip(base_r["_hits"], r["_hits"])]
    mu = sum(d) / len(d)
    se = math.sqrt(sum((x - mu) ** 2 for x in d) / max(1, len(d) - 1) / len(d))
    need = max(cfg.get("improve_min_gain", 0.05), 2 * se)
    deltas = {"guess matched your question": [base_r["hit_rate"], r["hit_rate"]], "avg model latency ms": [base_r["ms"], r["ms"]],
              "unparseable replies": [base_r["fails"], r["fails"]], "held-out cases": [base_r["n"], r["n"]]}
    if r["ms"] > base_r["ms"] * 1.25 + 50:
        ok, why = False, "slower than baseline"
    elif r["fails"] > base_r["fails"]:
        ok, why = False, "more unparseable replies than baseline"
    elif mu < need:
        ok, why = False, f"gain {mu:.3f} below noise threshold {need:.3f}"
    else:
        ok, why = True, f"gain {mu:.3f} > {need:.3f}"
    openers = {}
    for e in test:
        w = " ".join(e["final"].lower().split()[:2])
        openers[w] = openers.get(w, 0) + 1
    top = max(openers, key=openers.get) if openers else ""
    rc = (f"On {base_r['n']} held-out moments the current prompt matched your question {pc(base_r['hit_rate'])} of the time; "
          f"you usually start with “{top}”, which the guesses rarely do, so the wording, not the trigger, is off.")
    rg = {"check": f"held-out match rate ≥ {round(base_r['hit_rate'] + need, 3)}", "baseline": "fail",
          "candidate": "pass" if r["hit_rate"] >= base_r["hit_rate"] + need else "fail"}
    return {"kind": "prompt", "problem": "companion_misses", "prompt": v, "ok": ok, "why": why, "deltas": deltas,
            "root_cause": rc, "test_first": rg,
            "summary": (f"Your questions often differed from the companion's guesses. A reworded prediction prompt matched your real "
                        f"question {pc(r['hit_rate'])} of the time vs {pc(base_r['hit_rate'])} now, on {r['n']} past moments it hadn't seen.")}, why

# ---------------------------------------------------------------- optional code patch (local coding model)
def protected_ranges(src):
    rng = []
    for node in ast.walk(ast.parse(src)):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and node.name in PROTECTED_FUNCS:
            rng.append((node.lineno, node.end_lineno, node.name))
    return rng

def check_patch(cfg, patch, repo):
    """Static gate for model-written diffs. Returns (ok, reason)."""
    files = re.findall(r"^\+\+\+ (?:b/)?(\S+)", patch, re.M)
    if not files:
        return False, "not a unified diff"
    allow = set(cfg.get("improve_code_allowlist", []))
    changed = 0
    new_files = set(re.findall(r"^--- /dev/null\n\+\+\+ (?:b/)?(\S+)", patch, re.M))
    for f in set(files):
        if f.startswith(TEST_CASES_DIR) and f in new_files and f.endswith(".py") and ".." not in f:
            continue  # a brand-new failing test for this fix: allowed (existing tests can never be edited)
        if f in PROTECTED_FILES or f.startswith(PROTECTED_DIRS) or f not in allow or ".." in f:
            return False, f"file not allowed: {f}"
    cur_file, ranges = None, []
    for line in patch.splitlines():
        if line.startswith("+++ "):
            cur_file = re.sub(r"^\+\+\+ (?:b/)?", "", line).strip()
            src = (repo / cur_file).read_text() if (repo / cur_file).exists() else ""
            try:
                ranges = protected_ranges(src) if cur_file.endswith(".py") else []
            except SyntaxError:
                return False, "base file does not parse"
            continue
        m = re.match(r"^@@ -(\d+)(?:,(\d+))? \+\d+(?:,\d+)? @@", line)
        if m:
            old, cnt = int(m.group(1)), int(m.group(2) or 1)
            for a, z, name in ranges:
                if old <= z and old + cnt >= a:
                    return False, f"touches protected function {name}()"
            continue
        if line.startswith("-") and not line.startswith("---") and SAFETY_NET_RE.search(line):
            removed_line = line[1:].strip()
            if removed_line not in added_lines(patch):  # moved/reformatted is fine; deleted is not
                return False, f"removes a safety net: {removed_line[:60]}"
        if line.startswith(("+", "-")) and not line.startswith(("+++", "---")):
            changed += 1
            if line.startswith("+") and any(t in line for t in FORBIDDEN_TOKENS):
                return False, "adds a forbidden call/name"
    if changed > cfg.get("improve_max_diff_lines", 60) + 40 * len(new_files):
        return False, f"diff too large ({changed} lines)"
    return True, "ok"

def added_lines(patch):
    return {l[1:].strip() for l in patch.splitlines() if l.startswith("+") and not l.startswith("+++")}

def diff_size(patch, code_only=True):
    """(+added, -removed) lines, ignoring new test files and blank lines."""
    if code_only:
        patch = split_patch(patch)[1] or patch
    a = sum(1 for l in patch.splitlines() if l.startswith("+") and not l.startswith("+++") and l[1:].strip())
    r = sum(1 for l in patch.splitlines() if l.startswith("-") and not l.startswith("---") and l[1:].strip())
    return a, r

def split_patch(patch):
    """(test-only part, code part) of a unified diff, by file."""
    parts = re.split(r"(?m)^(?=--- )", patch)
    test = "".join(p_ for p_ in parts if re.search(r"^\+\+\+ (?:b/)?" + re.escape(TEST_CASES_DIR), p_, re.M))
    code = "".join(p_ for p_ in parts if p_.strip() and p_ not in test)
    return test, code

def code_candidate(cfg, problem):
    model = cfg.get("improve_code_model")
    if not model or problem["id"] != "companion_interrupts":
        return None, "code patches disabled" if not model else "no code generator for this problem"
    repo = repo_dir(cfg)
    src = (repo / "briefing.py").read_text()
    funcs = [n for n in ast.walk(ast.parse(src)) if isinstance(n, ast.FunctionDef) and n.name in ("stuck_score", "mode_threshold")]
    excerpt = "\n\n".join(f"# lines {n.lineno}-{n.end_lineno}\n" + "\n".join(src.splitlines()[n.lineno - 1:n.end_lineno]) for n in funcs)
    ev = comp_cases()
    tr, te = split(ev)
    rc = root_cause_companion(te, replay_companion(cfg, te, tr)["keep"]) if te else ""
    if not rc:
        return None, "no root cause found in your data; not patching blind"
    out, err = b.ollama_chat(dict(cfg, request_timeout_s=600), "You are a careful Python engineer who works test-first. Output ONLY a unified diff (git format, a/ b/ paths).",
                             f"Problem: {problem['text']}. Root cause from the user's data: {rc}\n"
                             f"1) First add a NEW file {TEST_CASES_DIR}test_<short_name>.py (unittest) that reproduces the root cause and "
                             f"FAILS on the current code. 2) Then make the smallest change to these functions in briefing.py so it passes. "
                             f"Max {cfg.get('improve_max_diff_lines', 60)} changed lines of code.\n\n{excerpt}", model=model)
    if err or "@@" not in out:
        return None, err or "model returned no diff"
    patch = out.strip().removeprefix("```diff").removeprefix("```").removesuffix("```").strip() + "\n"
    ok, why = check_patch(cfg, patch, repo)
    if not ok:
        return None, "patch rejected: " + why
    if not split_patch(patch)[0]:
        return None, "patch rejected: no new failing test under " + TEST_CASES_DIR
    add, rem = diff_size(patch)
    if add - rem > cfg.get("improve_max_net_growth", 20):
        return None, f"patch rejected: grows code by {add - rem} lines (limit {cfg.get('improve_max_net_growth', 20)}); prefer a smaller fix"
    return {"kind": "code", "problem": problem["id"], "patch": patch, "ok": True, "why": "static checks passed", "root_cause": rc,
            "test_first": {"check": "new test in " + TEST_CASES_DIR, "baseline": "unchecked", "candidate": "unchecked"},
            "summary": f"A local coding model ({model}) proposed a small change to how 'stuck' is scored.", "deltas": {}}, "ok"

# ---------------------------------------------------------------- git gate
# Variables git exports while a hook runs (a user can export them too). Inherited, they would point
# the loop's git, and the tests it runs, at another repository's index. Every git call here names its
# repo explicitly, so they are dropped from every environment the loop hands down.
GIT_CONTEXT_VARS = ("GIT_DIR", "GIT_INDEX_FILE", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_PREFIX",
                    "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES")

def clean_env(**extra):
    env = {k: v for k, v in os.environ.items() if k not in GIT_CONTEXT_VARS}
    env.update(extra)
    return env

def git(repo, *args, check=True):
    r = subprocess.run(["git", "-c", "user.name=Briefing", "-c", "user.email=briefing@localhost", "-C", str(repo), *args],
                       capture_output=True, text=True, timeout=120, env=clean_env())
    if check and r.returncode:
        raise RuntimeError(f"git {' '.join(args)}: {r.stderr.strip()[:300]}")
    return r.stdout.strip()

def repo_ok(repo):
    if not (repo / ".git").exists():
        return False, "app dir is not a git repo (re-run install.sh)"
    if git(repo, "status", "--porcelain", "--untracked-files=no"):
        return False, "app dir has uncommitted edits; not touching it"
    mem = (b.HOME / "memory").resolve()
    if repo == mem or mem in repo.parents or repo in mem.parents:
        return False, "repo overlaps memory folder"
    return True, ""

def eval_in_worktree(cfg, wt, home):
    """Re-run the companion replay with the candidate's own code (for code patches)."""
    code = ("import sys,json;sys.path.insert(0,'.');import briefing as b,improve as i;b.set_home(sys.argv[1]);c=b.load_config();"
            "e=i.comp_cases();tr,te=i.split(e);r=i.replay_companion(c,te,tr);print(json.dumps(r))")
    r = subprocess.run([sys.executable, "-c", code, str(home)], cwd=wt, capture_output=True, text=True, timeout=600,
                       env=clean_env(BRIEFING_IGNORE_OVERRIDES="0"))
    return json.loads(r.stdout.strip().splitlines()[-1]) if r.returncode == 0 and r.stdout.strip() else None

def run_new_tests(wt, paths, env):
    """Runs a candidate's new test files by path, from the worktree root.

    Each file is discovered on its own, so it is imported as a top-level module and no other
    package called `tests` on the machine can shadow it (one in the user's site-packages did,
    which made every new test "fail" with an ImportError). Returns {"ok", "ran", "why"}.
    """
    ok, ran, why = True, True, ""
    for path in paths:
        folder, name = os.path.split(path)
        r = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", folder or ".", "-t", folder or ".", "-p", name],
                           cwd=wt, capture_output=True, text=True, timeout=600, env=env)
        out = r.stderr + r.stdout
        if "Failed to import test module" in out or re.search(r"^Ran 0 tests", out, re.M):
            ran = False
            why = next((l for l in out.splitlines() if l.startswith(("ImportError", "ModuleNotFoundError", "SyntaxError"))),
                       "no tests found")
        ok = ok and r.returncode == 0
    return {"ok": ok and ran, "ran": ran, "why": why}


def gate(cfg, cand):
    """Branch + full tests (+ replay for code). On success returns proposal dict, else (None, reason)."""
    repo = repo_dir(cfg)
    ok, why = repo_ok(repo)
    if not ok:
        return None, why
    if not cand.get("root_cause"):
        return None, "no root-cause diagnosis; refusing to patch blind"
    tf = cand.get("test_first") or {}
    if cand["kind"] != "code" and not (tf.get("baseline") == "fail" and tf.get("candidate") == "pass"):
        return None, "failing-check-first rule not met (check must fail now and pass with the change)"
    cid = time.strftime("%Y%m%d-%H%M") + "-" + secrets.token_hex(3)
    branch = f"improve/{cid}"
    wt = Path(tempfile.mkdtemp(prefix="briefing-wt-"))
    shutil.rmtree(wt)
    git(repo, "worktree", "add", "-q", "-b", branch, str(wt), "HEAD")
    keep = False
    try:
        if cand["kind"] == "param":
            for k, v in cand["change"].items():
                lo, hi = BOUNDS[k]
                if not lo <= v <= hi:
                    return None, f"{k}={v} outside safe bounds"
            t = b.jload(wt / "tunables.json", {}) if (wt / "tunables.json").exists() else {}
            t.update(cand["change"])
            (wt / "tunables.json").write_text(json.dumps(t, indent=2, sort_keys=True) + "\n")
        elif cand["kind"] == "prompt":
            pr = b.jload(wt / "prompts.json", {}) if (wt / "prompts.json").exists() else {}
            pr["anticipate_sys"] = cand["prompt"]
            (wt / "prompts.json").write_text(json.dumps(pr, indent=2) + "\n")
        else:
            test_part, code_part = split_patch(cand["patch"])
            if not test_part or not code_part:
                return None, "code candidates need a new failing test and a fix"
            pf = Path(tempfile.mkdtemp()) / "c.patch"
            for part in (test_part, code_part):
                pf.write_text(part)
                if subprocess.run(["git", "-C", str(wt), "apply", "--check", str(pf)], capture_output=True, env=clean_env()).returncode:
                    return None, "patch does not apply"
            pf.write_text(test_part)
            subprocess.run(["git", "-C", str(wt), "apply", str(pf)], check=True, env=clean_env())
            new_tests = re.findall(r"^\+\+\+ (?:b/)?(\S+)", test_part, re.M)
            env = clean_env(BRIEFING_HOME=tempfile.mkdtemp(prefix="briefing-red-"))
            red = run_new_tests(wt, new_tests, env)
            if not red["ran"]:
                return None, "new test doesn't run (it can't be imported): " + red["why"]
            if red["ok"]:
                return None, "new test passes before the fix (it doesn't reproduce the root cause)"
            pf.write_text(code_part)
            subprocess.run(["git", "-C", str(wt), "apply", str(pf)], check=True, env=clean_env())
            if not run_new_tests(wt, new_tests, env)["ok"]:
                return None, "new test still fails after the fix"
            cand["test_first"] = {"check": ", ".join(new_tests), "baseline": "fail", "candidate": "pass"}
        git(wt, "add", "-A")
        git(wt, "commit", "-q", "-m", f"improve: {cand['summary'][:72]}")
        changed = git(repo, "diff", "--name-only", "HEAD", branch).split()
        for f in changed:
            if f.startswith(TEST_CASES_DIR) and cand["kind"] == "code":
                continue
            if f in PROTECTED_FILES or f.startswith(PROTECTED_DIRS):
                return None, f"candidate touched protected file {f}"
            if cand["kind"] != "code" and f not in ("tunables.json", "prompts.json"):
                return None, f"unexpected file {f}"
        scratch = Path(tempfile.mkdtemp(prefix="briefing-test-home-"))
        cmd = cfg.get("improve_test_cmd") or [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-q"]
        t0 = time.time()
        r = subprocess.run(cmd, cwd=wt, capture_output=True, text=True, timeout=1800,
                           env=clean_env(BRIEFING_HOME=str(scratch)))
        shutil.rmtree(scratch, ignore_errors=True)
        if r.returncode:
            return None, "test suite failed: " + (r.stderr or r.stdout).strip().splitlines()[-1][:200] if (r.stderr or r.stdout).strip() else "test suite failed"
        test_s = round(time.time() - t0, 1)
        if cand["kind"] == "code":
            base_r = replay_companion(cfg, *reversed(split(comp_cases())))
            cand_r = eval_in_worktree(cfg, wt, b.HOME)
            if not cand_r:
                return None, "replay failed on patched code"
            ok, why, deltas = judge(cfg, base_r, cand_r, "companion")
            cand["deltas"] = deltas
            if not ok:
                return None, why
        diff = git(repo, "diff", "HEAD", branch)
        add, rem = diff_size(diff, code_only=True) if cand["kind"] == "code" else diff_size(diff, code_only=False)
        if cand["kind"] == "code" and add - rem > cfg.get("improve_max_net_growth", 20):
            return None, f"grows code by {add - rem} lines without need"
        keep = True
        return {"id": cid, "ts": int(time.time()), "kind": cand["kind"], "problem": cand["problem"], "summary": cand["summary"],
                "deltas": strip_private(cand["deltas"]), "why": cand["why"], "diff": diff[:20000], "branch": branch,
                "base_commit": git(repo, "rev-parse", "HEAD"), "tests": f"passed in {test_s}s", "status": "pending",
                "root_cause": cand["root_cause"], "test_first": cand["test_first"],
                "change": cand.get("change"), "prompt": cand.get("prompt"),
                "lines": {"added": add, "removed": rem, "net": add - rem},
                "verified": {"full_suite": True, "held_out_replay": True, "failing_check_first": True}}, "ok"
    finally:
        git(repo, "worktree", "remove", "--force", str(wt), check=False)
        if not keep:
            git(repo, "branch", "-D", branch, check=False)

def strip_private(d):
    return {k: v for k, v in d.items() if not k.startswith("_")}

# ---------------------------------------------------------------- orchestration
def on_battery():
    if not b.is_mac():
        return False
    try:
        return "Battery Power" in subprocess.run(["pmset", "-g", "batt"], capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return False

def mem_hash():
    import hashlib
    h = hashlib.sha256()
    mem = b.HOME / "memory"
    for p in sorted(mem.rglob("*")) if mem.exists() else []:
        if p.is_file():
            st = p.stat()
            h.update(f"{p.relative_to(mem)}:{st.st_size}:{st.st_mtime_ns}".encode())
    return h.hexdigest()

def run_audit(cfg):
    """L0 Audit-only execution: observes metrics, indexes codebase, and ranks problems without code or branch edits."""
    return run(cfg, force=True, mode="audit")

def cancel(cfg, reason="user cancelled"):
    lock = idir() / ".lock"
    lock.unlink(missing_ok=True)
    transition("CANCELLED", actor="user", reason=reason)
    transition("IDLE", actor="engine", reason="reset after cancel")
    runlog({"result": "cancelled", "reason": reason})
    return {"ok": True, "state": "IDLE", "reason": reason}

def run(cfg, force=False, mode=None):
    eff_mode = current_mode(cfg, mode)
    op_id = f"op-{time.strftime('%Y%m%d-%H%M%S')}-{secrets.token_hex(2)}"
    if not cfg.get("improve_enabled", True) and not force:
        transition("BLOCKED", op_id=op_id, reason="disabled", mode=eff_mode)
        return {"skipped": "disabled"}
    if not force and on_battery():
        transition("BLOCKED", op_id=op_id, reason="on battery", mode=eff_mode)
        runlog({"result": "skipped", "reason": "on battery"}); return {"skipped": "on battery"}
    free = shutil.disk_usage(b.HOME).free / 1e9
    if free < cfg.get("improve_min_free_gb", 2):
        transition("BUDGET_EXCEEDED", op_id=op_id, reason=f"low disk ({free:.1f} GB)", mode=eff_mode)
        runlog({"result": "skipped", "reason": f"low disk ({free:.1f} GB)"}); return {"skipped": "low disk"}
    lock = idir() / ".lock"
    if lock.exists() and time.time() - lock.stat().st_mtime < 3 * 3600:
        return {"skipped": "already running"}
    lock.write_text(str(os.getpid()))
    before = mem_hash()
    n_props = len(props_load())
    try:
        transition("OBSERVING", op_id=op_id, reason=f"starting {eff_mode} cycle", mode=eff_mode)
        rep = _run(cfg, mode=eff_mode, op_id=op_id)
        if mem_hash() != before:  # the loop must never write memories; if something did, nothing from this run is kept
            ps = props_load()
            for p in ps[n_props:]:
                git(repo_dir(cfg), "branch", "-D", p["branch"], check=False)
            props_save(ps[:n_props])
            transition("FAILED", op_id=op_id, reason="memory changed during the run", mode=eff_mode)
            runlog({"result": "aborted", "reason": "memory changed during the run"})
            return {"aborted": "memory changed during improve run", "proposals": []}
        transition("RECORDED", op_id=op_id, reason=rep.get("result", "completed"), mode=eff_mode, output_refs=rep.get("proposals", []))
        transition("IDLE", op_id=op_id, reason="cycle complete", mode=eff_mode)
        return rep
    finally:
        lock.unlink(missing_ok=True)

GENERATORS = {"companion_interrupts": [tune_companion], "companion_misses": [tune_prompt], "nextmove_dismissed": [tune_nextmove]}

def _run(cfg, mode="guided", op_id=""):
    m = metrics(cfg)
    transition("ANALYZING", op_id=op_id, reason="analyzing telemetry and quality signals", mode=mode)
    probs = problems(cfg, m)
    if mode == "audit":
        transition("REVIEWING", op_id=op_id, reason=f"audit mode (L0): {len(probs)} opportunity(s) ranked; write operations disabled", mode=mode)
        report = {"result": "audit", "mode": "audit", "metrics": m, "problems": probs, "proposals": [],
                  "codebase": index_codebase(cfg),
                  "notes": [f"{p['id']} (priority {p.get('priority', 0)}): {p['text']}" for p in probs] or ["audit clean: no change needed"]}
        report["retro"] = write_retro(cfg, m, probs, report)
        runlog({"result": "audit", "mode": "audit", "problems": [p["id"] for p in probs],
                "notes": report["notes"], "proposals": []})
        return report
    pending = {p["problem"] for p in props_load() if p["status"] == "pending" and p.get("kind") != "retro"}
    report = {"result": "no change needed", "mode": mode, "metrics": m, "problems": probs, "proposals": [], "notes": []}
    for prob in [p for p in probs if p["fixable"]][:2]:
        if prob["id"] in pending:
            report["notes"].append(f"{prob['id']}: a proposal is already waiting for you")
            continue
        transition("PROPOSING", op_id=op_id, reason=f"generating candidates for {prob['id']}", mode=mode)
        cands, reasons = [], []
        for gen in GENERATORS.get(prob["id"], []):  # cheapest first: params/prompts, then optional code
            cand, why = gen(cfg)
            reasons.append(why)
            if cand and cand["ok"]:
                cands.append(cand)
        if not cands:
            cand, why = code_candidate(cfg, prob)
            reasons.append(why)
            if cand:
                cands.append(cand)
        transition("REVIEWING", op_id=op_id, reason=f"adversarial review of {len(cands)} candidate(s)", mode=mode)
        winner = min(cands, key=rank_key) if cands else None
        if not winner:
            report["notes"].append(f"{prob['id']}: no change needed ({'; '.join(reasons)})")
            continue
        if is_duplicate_rejected(winner, mode):
            report["notes"].append(f"{prob['id']}: skipped duplicate of already-rejected proposal")
            continue
        transition("BASELINING", op_id=op_id, reason=f"isolating worktree for {winner['kind']} candidate", mode=mode)
        transition("IMPLEMENTING", op_id=op_id, reason=f"applying {winner['kind']} candidate in isolated branch", mode=mode)
        transition("VERIFYING", op_id=op_id, reason="running test suite and held-out replay", mode=mode)
        prop, why = gate(cfg, winner)
        if not prop:
            report["notes"].append(f"{prob['id']}: candidate discarded ({why})")
            continue
        transition("EVALUATING", op_id=op_id, reason=why, mode=mode, output_refs=[prop["id"]])
        prop["contract"] = iteration_contract(cfg, mode, prob, winner)
        ps = props_load(); ps.append(prop); props_save(ps)
        report["proposals"].append(prop["id"])
        transition("APPROVAL_PENDING", op_id=op_id, reason=f"proposal {prop['id']} ready for review", mode=mode, output_refs=[prop["id"]])
        if prop["kind"] == "param" and (cfg.get("improve_auto_apply_params") or mode == "controlled_autonomous"):
            decide(cfg, prop["id"], "approve", auto=True)
    if not probs:
        report["notes"].append("no change needed: all metrics within targets or not enough data yet")
    report["result"] = "proposal" if report["proposals"] else "no change needed"
    report["retro"] = write_retro(cfg, m, probs, report)
    runlog({"result": report["result"], "mode": mode, "problems": [p["id"] for p in probs],
            "notes": report["notes"], "proposals": report["proposals"]})
    return report

def retro_items(cfg, m, probs, report):
    """Root-cause environment improvements (missing checks/tests, confusing setup). Suggestions only; nothing is changed."""
    out = []
    ev = b.comp_load()["events"]
    old = sum(1 for e in ev if not isinstance(e.get("sig"), dict))
    if old >= 10:
        out.append(("missing check", f"{old} older companion events have no signal snapshot, so replay can't learn from them. "
                                     "They age out naturally; nothing to do unless you want to clear them."))
    if m["briefing"]["n"] == 0:
        out.append(("missing signal", "No briefing has a 👍/👎 rating yet, so briefing quality can't be measured. Rate a few on the Today page."))
    user = b.jload(b.CONFIG_PATH, {})
    tun = b.load_overrides("tunables.json")
    shadow = [k for k in tun if k in user and user[k] != b.DEFAULTS.get(k) and user[k] != tun[k]]
    if shadow:
        out.append(("confusing setup", f"config.json sets {', '.join(shadow)}, which hides the approved tuning for "
                                       "the same keys. Remove them from config.json if you want the tuned values."))
    for p in probs:
        if not p["fixable"]:
            out.append(("missing test", f"'{p['text']}' has no automatic fix or replay test yet; it needs labelled examples first."))
    if any("uncommitted" in n for n in report["notes"]):
        out.append(("confusing setup", "The app folder has hand edits, so the loop can't branch safely. Commit or revert them "
                                       "(git -C ~/Briefing/app status)."))
    return out[:5]

def write_retro(cfg, m, probs, report):
    items = retro_items(cfg, m, probs, report)
    day = time.strftime("%Y-%m-%d")
    lines = [f"# Retro {day}", "", "## What happened"] + [f"- {n}" for n in report["notes"] or ["no candidates"]] + \
            ["", "## Root causes"] + [f"- {p_['text']}" for p_ in probs] + ["", "## Environment improvements (proposals; nothing applied)"] + \
            [f"- **{k}**: {t}" for k, t in items]
    (idir() / f"retro-{day}.md").write_text("\n".join(lines) + "\n")
    ps = props_load()
    have = {p_["summary"] for p_ in ps if p_.get("kind") == "retro" and p_["status"] in ("pending", "accepted")}
    for k, t in items:
        if t not in have:
            ps.append({"id": time.strftime("%Y%m%d") + "-r" + secrets.token_hex(2), "ts": int(time.time()), "kind": "retro",
                       "problem": k, "summary": t, "deltas": {}, "diff": "", "branch": "", "status": "pending",
                       "why": "retro suggestion: approval only records it in ~/Briefing/improve/backlog.json"})
    mine = set(report["proposals"])  # keep this run's real proposals newest
    props_save([p_ for p_ in ps if p_["id"] not in mine] + [p_ for p_ in ps if p_["id"] in mine])
    return items

KIND_RANK = {"param": 0, "prompt": 1, "code": 2}

def rank_key(c):
    """Smallest change first: setting < prompt < code; among code, net deletions beat additions."""
    if c["kind"] == "code":
        a, r = diff_size(c["patch"])
        return (2, a - r, a + r)
    return (KIND_RANK[c["kind"]], 0, len(c.get("change") or {}) or 1)

def run_async(cfg, mode=""):
    eff = mode if mode in MODES else None
    threading.Thread(target=run, args=(cfg, True, eff), daemon=True).start()
    return {"started": True, "mode": current_mode(cfg, eff)}

def restart_agents():
    if b.is_mac():
        subprocess.run(["launchctl", "kickstart", "-k", f"gui/{os.getuid()}/com.dayflowbriefing.dashboard"], capture_output=True)

def decide(cfg, pid, decision, auto=False):
    ps = props_load()
    p = next((x for x in ps if x["id"] == pid), None)
    if not p:
        raise KeyError(pid)
    repo = repo_dir(cfg)
    if p.get("kind") == "retro":  # suggestions only: approval records it on a backlog, never changes code or memory
        if decision not in ("approve", "reject") or p["status"] != "pending":
            return {"error": "retro items can only be accepted or dismissed once"}
        p.update(status="accepted" if decision == "approve" else "rejected", decided=int(time.time()))
        if decision == "approve":
            bl = b.jload(idir() / "backlog.json", [])
            bl.append({"ts": int(time.time()), "kind": p["problem"], "text": p["summary"]})
            b.jsave(idir() / "backlog.json", bl)
        props_save(ps)
        return {"ok": True, "status": p["status"]}
    if decision == "approve":
        if p["status"] != "pending":
            return {"error": f"proposal is {p['status']}"}
        ok, why = repo_ok(repo)
        if not ok:
            return {"error": why}
        bk = idir() / "backups"
        bk.mkdir(exist_ok=True)
        git(repo, "bundle", "create", str(bk / f"{pid}-before.bundle"), "HEAD", "--quiet", check=False)
        git(repo, "merge", "--no-ff", "-q", "-m", f"Approve improvement {pid}: {p['summary'][:60]}", p["branch"])
        p.update(status="approved", merge_commit=git(repo, "rev-parse", "HEAD"), decided=int(time.time()), auto=auto)
        git(repo, "branch", "-D", p["branch"], check=False)
        transition("MERGED", actor="auto" if auto else "user", reason=f"approved {pid}", input_refs=[pid], output_refs=[p["merge_commit"]])
        transition("IDLE", actor="engine", reason="merge recorded")
        restart_agents()
    elif decision == "reject":
        if p["status"] != "pending":
            return {"error": f"proposal is {p['status']}"}
        git(repo, "branch", "-D", p["branch"], check=False)
        p.update(status="rejected", decided=int(time.time()))
        transition("REJECTED", actor="user", reason=f"rejected {pid}", input_refs=[pid])
        transition("IDLE", actor="engine", reason="rejection recorded")
    elif decision == "undo":
        if p["status"] != "approved":
            return {"error": "only approved changes can be undone"}
        ok, why = repo_ok(repo)
        if not ok:
            return {"error": why}
        git(repo, "revert", "--no-edit", "-m", "1", p["merge_commit"])
        p.update(status="reverted", revert_commit=git(repo, "rev-parse", "HEAD"), decided=int(time.time()))
        transition("REVERTED", actor="user", reason=f"reverted {pid}", input_refs=[pid], output_refs=[p["revert_commit"]])
        transition("IDLE", actor="engine", reason="revert recorded")
        restart_agents()
    else:
        raise ValueError("decision must be approve, reject or undo")
    props_save(ps)
    b.telemetry("improve", decision=decision, change_kind=p["kind"])
    return {"ok": True, "status": p["status"]}

def overview(cfg):
    repo = repo_dir(cfg)
    m = metrics(cfg)
    mode = current_mode(cfg)
    return {
        "proposals": list(reversed(props_load()))[:20],
        "runs": list(reversed(runs_load(10))),
        "metrics": m,
        "problems": problems(cfg, m),
        "state": state_load(),
        "transitions": list(reversed(transitions_load(12))),
        "mode": mode,
        "modes": MODES,
        "codebase": index_codebase(cfg),
        "repo": (repo / ".git").exists(),
        "auto_apply_params": bool(cfg.get("improve_auto_apply_params")),
        "code_model": cfg.get("improve_code_model") or "",
    }
