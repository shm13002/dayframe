"""Self-improvement loop, Obsidian vault and Things sync. Run: python3 -m unittest discover -s tests"""
import hashlib, json, os, shutil, subprocess, sys, tempfile, time, unittest
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent)); sys.path.insert(0, str(HERE))
os.environ.setdefault("BRIEFING_HOME", tempfile.mkdtemp())
os.environ["BRIEFING_IGNORE_OVERRIDES"] = "1"
import briefing as b  # noqa: E402
import improve  # noqa: E402
import mocks  # noqa: E402

OLL = mocks.FakeOllama()
HI = {"dwell_s": 900, "scroll_reversals": 6, "rereads": 3, "search_switches": 2, "idle_s": 60, "present": True, "typing_cpm": 5, "time_on_task_s": 1500}
LO = {"dwell_s": 300, "scroll_reversals": 3, "rereads": 1, "search_switches": 1, "idle_s": 5, "present": True, "typing_cpm": 40, "time_on_task_s": 400}
PY = sys.executable

def tree_hash(d):
    h = hashlib.sha256()
    for p in sorted(Path(d).rglob("*")):
        if p.is_file():
            h.update(str(p.relative_to(d)).encode()); h.update(p.read_bytes())
    return h.hexdigest()

class ImproveBase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        b.set_home(self.tmp / "home"); b.HOME.mkdir(parents=True)
        self.repo = self.tmp / "app"; self.repo.mkdir()
        for f in ("briefing.py", "improve.py", "tunables.json", "prompts.json"):
            shutil.copy(HERE.parent / f, self.repo / f)
        (self.repo / "tests").mkdir()
        (self.repo / "tests" / "test_ok.py").write_text("import unittest\nclass T(unittest.TestCase):\n    def test_ok(self): pass\n")
        for c in (["init", "-q"], ["add", "-A"], ["commit", "-q", "-m", "install"]):
            subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "-C", str(self.repo)] + c, check=True)
        self.base_cfg = {"model": "m", "ollama_url": OLL.url, "request_timeout_s": 10, "companion_sensitivity": 1.0,
                         "improve_repo": str(self.repo), "improve_test_cmd": [PY, "-m", "unittest", "discover", "-s", "tests", "-q"],
                         "improve_min_free_gb": 0}
        self.write_cfg()
        b.mem_init()
        OLL.mode = "ok"
        self._app = b.APP_DIR
        b.APP_DIR = self.repo
        os.environ["BRIEFING_TEST_NORUN"] = "1"

    def tearDown(self):
        b.APP_DIR = self._app
        improve.ask_model = self._ask if hasattr(self, "_ask") else improve.ask_model

    def write_cfg(self, **kw):
        self.base_cfg.update(kw)
        b.CONFIG_PATH.write_text(json.dumps(self.base_cfg))
        self.cfg = b.load_config()

    def seed_companion(self, n=60, separable=True):
        db = b.comp_load()
        now = time.time()
        for i in range(n):
            hit = i % 2 == 0
            sig = HI if (hit or not separable) else LO
            db["events"].append({"ts": int(now - (n - i) * 7000), "id": f"e{i}", "mode": "coding", "app": "Cursor", "title": f"file{i}.py",
                                 "subject": "python", "predicted": ["Why is this failing?"], "chosen_index": 0 if hit else None,
                                 "final": "Why is this failing?" if hit else "", "outcome": "chosen" if hit else "ignored",
                                 "ratio": 1.0 if hit else 0.0, "hit": hit, "diff": "", "snippet": "Traceback: KeyError user_id",
                                 "levels": [], "fallback": False, "score": None, "threshold": None, "sig": dict(sig), "error_visible": False})
        b.comp_save(db)

    def branches(self):
        return subprocess.run(["git", "-C", str(self.repo), "branch", "--list", "improve/*"], capture_output=True, text=True).stdout.split()


class TestImproveLoop(ImproveBase):
    def test_improving_param_proposed_then_approved_and_undone(self):
        self.seed_companion()
        mem_before = tree_hash(b.MEM)
        rep = improve.run(self.cfg, force=True)
        self.assertEqual(len(rep["proposals"]), 1, rep["notes"])
        p = improve.props_load()[-1]
        self.assertEqual((p["kind"], p["status"], p["problem"]), ("param", "pending", "companion_interrupts"))
        self.assertIn("tunables.json", p["diff"]); self.assertIn("companion_threshold_base", p["diff"])
        self.assertLess(p["deltas"]["companion: wasted interruptions"][1], p["deltas"]["companion: wasted interruptions"][0])
        self.assertEqual(json.loads((self.repo / "tunables.json").read_text()), {})  # never auto-applied
        self.assertEqual(tree_hash(b.MEM), mem_before)  # memory untouched
        # approval: merge, backup bundle, config now sees the tuned value
        os.environ["BRIEFING_IGNORE_OVERRIDES"] = "0"
        try:
            self.assertEqual(improve.decide(self.cfg, p["id"], "approve")["status"], "approved")
            tuned = json.loads((self.repo / "tunables.json").read_text())
            self.assertGreater(tuned["companion_threshold_base"], 0.75)
            self.assertEqual(b.load_config()["companion_threshold_base"], tuned["companion_threshold_base"])
            self.assertTrue(list((b.HOME / "improve" / "backups").glob("*.bundle")))
            self.assertEqual(self.branches(), [])
            # briefing card disappears once approved; undo reverts the merge
            self.assertEqual(improve.decide(self.cfg, p["id"], "undo")["status"], "reverted")
            self.assertEqual(json.loads((self.repo / "tunables.json").read_text()), {})
            self.assertEqual(b.load_config()["companion_threshold_base"], 0.75)
            self.assertIn("error", improve.decide(self.cfg, p["id"], "undo"))
        finally:
            os.environ["BRIEFING_IGNORE_OVERRIDES"] = "1"

    def test_user_set_value_beats_tunables(self):
        (self.repo / "tunables.json").write_text(json.dumps({"companion_threshold_base": 0.85}))
        os.environ["BRIEFING_IGNORE_OVERRIDES"] = "0"
        try:
            self.assertEqual(b.load_config()["companion_threshold_base"], 0.85)
            self.write_cfg(companion_threshold_base=0.6)
            self.assertEqual(b.load_config()["companion_threshold_base"], 0.6)
        finally:
            os.environ["BRIEFING_IGNORE_OVERRIDES"] = "1"

    def test_non_improving_history_means_no_change(self):
        self.seed_companion(separable=False)  # ignored and used guesses look identical: nothing to tune
        rep = improve.run(self.cfg, force=True)
        self.assertEqual(rep["proposals"], [])
        self.assertTrue(any("no change needed" in n for n in rep["notes"]), rep["notes"])
        self.assertEqual(self.branches(), [])
        self.assertEqual(improve.runs_load()[-1]["result"], "no change needed")

    def test_not_enough_data_is_no_change(self):
        self.seed_companion(n=10)
        rep = improve.run(self.cfg, force=True)
        self.assertEqual(rep["proposals"], []); self.assertEqual(rep["problems"], [])

    def test_failing_test_suite_discards_candidate(self):
        self.seed_companion()
        self.write_cfg(improve_test_cmd=[PY, "-c", "import sys; print('boom'); sys.exit(1)"])
        rep = improve.run(self.cfg, force=True)
        self.assertEqual(rep["proposals"], [])
        self.assertTrue(any("test suite failed" in n for n in rep["notes"]), rep["notes"])
        self.assertEqual(self.branches(), [])

    def test_regressing_candidate_rejected_by_judge(self):
        base = {"n": 20, "waste": 0.5, "good_kept": 10, "_bad": [1] * 10 + [0] * 10, "_good": [0] * 10 + [1] * 10}
        lose = {"n": 20, "waste": 0.0, "good_kept": 6, "_bad": [0] * 20, "_good": [0] * 14 + [1] * 6}
        ok, why, _ = improve.judge(self.cfg, base, lose, "x")
        self.assertFalse(ok); self.assertIn("lose", why)
        tiny = {"n": 20, "waste": 0.45, "good_kept": 10, "_bad": [0] + [1] * 9 + [0] * 10, "_good": base["_good"]}
        ok, why, _ = improve.judge(self.cfg, base, tiny, "x")
        self.assertFalse(ok); self.assertIn("noise", why)
        good = {"n": 20, "waste": 0.0, "good_kept": 10, "_bad": [0] * 20, "_good": base["_good"]}
        self.assertTrue(improve.judge(self.cfg, base, good, "x")[0])
        small = dict(base, n=6, _bad=[1] * 6, _good=[0] * 6)
        self.assertFalse(improve.judge(self.cfg, small, dict(small, _bad=[0] * 6, waste=0), "x")[0])

    def seed_prompt_cases(self, n=30):
        db = b.comp_load()
        for i in range(n):
            db["events"].append({"ts": int(time.time() - 1000 + i), "mode": "coding", "app": "Cursor", "title": "a.py", "subject": "python",
                                 "predicted": ["What does this do?"], "final": f"why does test {i} fail", "outcome": "typed", "hit": False,
                                 "ratio": 0.1, "diff": "", "snippet": f"FAILED test_{i}", "levels": []})
        b.comp_save(db)

    def fake_model(self, better_ms=10, base_ms=10):
        self._ask = improve.ask_model
        def ask(cfg, system, user):
            if "You improve system prompts" in system:
                return "not a valid prompt", None, 5
            n = user.split("FAILED test_")[1].split()[0] if "FAILED test_" in user else "0"
            if improve.PROMPT_TWEAKS[0].strip() in system:
                return json.dumps({"questions": [{"text": f"why does test {n} fail"}]}), None, better_ms
            return json.dumps({"questions": [{"text": "What does this do?"}]}), None, base_ms
        improve.ask_model = ask

    def test_prompt_variant_wins_on_held_out_cases(self):
        self.seed_prompt_cases()
        self.fake_model()
        cand, why = improve.tune_prompt(self.cfg)
        self.assertTrue(cand["ok"], why)
        prop, why = improve.gate(self.cfg, cand)
        self.assertIsNotNone(prop, why)
        self.assertEqual(prop["kind"], "prompt"); self.assertIn("prompts.json", prop["diff"])
        self.assertEqual(prop["deltas"]["guess matched your question"], [0.0, 1.0])

    def test_slower_prompt_variant_rejected(self):
        self.seed_prompt_cases()
        self.fake_model(better_ms=500, base_ms=10)
        cand, why = improve.tune_prompt(self.cfg)
        self.assertFalse(cand["ok"]); self.assertIn("slower", why)

    def test_reject_and_auto_apply(self):
        self.seed_companion()
        improve.run(self.cfg, force=True)
        p = improve.props_load()[-1]
        self.assertEqual(improve.decide(self.cfg, p["id"], "reject")["status"], "rejected")
        self.assertEqual(self.branches(), [])
        self.assertEqual(json.loads((self.repo / "tunables.json").read_text()), {})
        self.write_cfg(improve_auto_apply_params=True)
        improve.run(self.cfg, force=True)
        p2 = improve.props_load()[-1]
        self.assertEqual((p2["status"], p2.get("auto")), ("approved", True))

    def test_dirty_repo_or_skips(self):
        self.seed_companion()
        (self.repo / "briefing.py").write_text((self.repo / "briefing.py").read_text() + "\n# local edit\n")
        rep = improve.run(self.cfg, force=True)
        self.assertTrue(any("uncommitted" in n for n in rep["notes"]), rep["notes"])
        self.write_cfg(improve_min_free_gb=10 ** 15)
        self.assertEqual(improve.run(self.cfg, force=True), {"skipped": "low disk"})
        orig = improve.on_battery
        improve.on_battery = lambda: True
        try:
            self.assertEqual(improve.run(self.cfg)["skipped"], "on battery")
        finally:
            improve.on_battery = orig

    def test_pending_proposal_shows_in_briefing_and_api(self):
        self.seed_companion()
        improve.run(self.cfg, force=True)
        os.environ["BRIEFING_TEST_ANSWER"] = ""
        out = b.cmd_brief(self.cfg, force=True, interactive=False)
        self.assertIn("Suggested improvement", out)
        ov = b.ext_get(self.cfg, "/api/improve", {})
        self.assertEqual(ov["proposals"][0]["status"], "pending"); self.assertTrue(ov["repo"])


class TestPatchSafety(ImproveBase):
    def hunk(self, func, path="briefing.py", body="+    x = 1\n"):
        src = (self.repo / path).read_text() if (self.repo / path).exists() else ""
        line = next(i for i, l in enumerate(src.splitlines(), 1) if l.startswith(f"def {func}(")) if func else 1
        return f"--- a/{path}\n+++ b/{path}\n@@ -{line + 1},1 +{line + 1},2 @@\n {src.splitlines()[line] if src else ''}\n{body}"

    def test_privacy_and_approval_code_is_off_limits(self):
        for f in ("blocked", "automation_run", "automation_decide", "anticipate", "cmd_forget", "make_handler", "telemetry",
                  "things_sync", "vault_sync", "do_resume", "load_config", "cli_chat", "cli_bin"):
            ok, why = improve.check_patch(self.cfg, self.hunk(f), self.repo)
            self.assertFalse(ok, f); self.assertIn("protected", why)
            self.assertIn(f, improve.PROTECTED_FUNCS)

    def test_file_allowlist_size_and_tokens(self):
        self.assertTrue(improve.check_patch(self.cfg, self.hunk("stuck_score"), self.repo)[0])
        self.assertFalse(improve.check_patch(self.cfg, self.hunk(None, "tests/test_ok.py"), self.repo)[0])
        cfg = dict(self.cfg, improve_code_allowlist=["briefing.py", "improve.py", "install.sh"])  # even if misconfigured
        self.assertFalse(improve.check_patch(cfg, self.hunk(None, "improve.py"), self.repo)[0])
        self.assertFalse(improve.check_patch(cfg, self.hunk(None, "install.sh"), self.repo)[0])
        self.assertFalse(improve.check_patch(self.cfg, self.hunk(None, "dashboard.html"), self.repo)[0])
        big = self.hunk("stuck_score", body="".join(f"+    x{i} = {i}\n" for i in range(80)))
        self.assertIn("too large", improve.check_patch(self.cfg, big, self.repo)[1])
        for bad in ("+    subprocess.run(['rm'])\n", "+    cfg['blocklist'] = {}\n", "+    open(HOME / 'x', 'w')\n"):
            self.assertFalse(improve.check_patch(self.cfg, self.hunk("stuck_score", body=bad), self.repo)[0], bad)

    def test_code_candidate_from_model_goes_through_gate(self):
        self.seed_companion()
        src = (self.repo / "briefing.py").read_text().splitlines()
        i = next(n for n, l in enumerate(src, 1) if "th = float(cfg.get(\"companion_threshold_base\"" in l)
        new = src[i - 1].replace('0.75))', '0.75)) + 0.12')
        patch = (f"--- a/briefing.py\n+++ b/briefing.py\n@@ -{i - 1},3 +{i - 1},3 @@\n {src[i - 2]}\n-{src[i - 1]}\n+{new}\n {src[i]}\n")
        test_src = ["import unittest", "import briefing as b", "class T(unittest.TestCase):",
                    "    def test_threshold_not_too_eager(self):",
                    "        c = dict(b.DEFAULTS, companion_sensitivity=1.0)",
                    "        self.assertGreaterEqual(b.mode_threshold(c, {'events': []}, 'coding'), 0.42)"]
        tpatch = "--- /dev/null\n+++ b/tests/improve_cases/test_threshold.py\n@@ -0,0 +1,%d @@\n" % len(test_src) + "".join("+" + l + "\n" for l in test_src)
        patch = tpatch + patch
        cand = {"kind": "code", "problem": "companion_interrupts", "patch": patch, "ok": True, "why": "", "summary": "raise threshold",
                "deltas": {}, "root_cause": "ignored guesses fire on weak signals", "test_first": {}}
        # rule: no diagnosis, no candidate; a fix without its own failing test is refused
        self.assertIn("root-cause", improve.gate(self.cfg, dict(cand, root_cause=""))[1])
        self.assertIn("failing test", improve.gate(self.cfg, dict(cand, patch=improve.split_patch(patch)[1]))[1])
        self.assertTrue(improve.check_patch(self.cfg, patch, self.repo)[0])
        prop, why = improve.gate(self.cfg, cand)
        self.assertIsNotNone(prop, why)
        self.assertIn("+ 0.12", prop["diff"]); self.assertIn("tests/improve_cases/test_threshold.py", prop["diff"])
        self.assertEqual((prop["test_first"]["baseline"], prop["test_first"]["candidate"]), ("fail", "pass"))
        self.assertTrue(all(prop["verified"].values()))
        weak = dict(cand, patch=tpatch.replace("0.42", "0.1") + improve.split_patch(patch)[1])  # test passes before the fix
        self.assertIn("passes before the fix", improve.gate(self.cfg, weak)[1])
        bad = dict(cand, patch=patch.replace("+ 0.12", "- 0.5"))  # interrupts more: must be discarded
        prop, why = improve.gate(self.cfg, bad)
        self.assertIsNone(prop)
        self.assertTrue("gain" in why or "still fails" in why, why)
        self.assertEqual(len(self.branches()), 1)  # only the first (kept) candidate's branch remains

    def test_git_only_touches_the_repo_it_names(self):
        # A git hook exports GIT_INDEX_FILE / GIT_DIR. Inherited, they would point the loop's git at
        # another repository; every git call here must ignore them.
        saved = {k: os.environ.get(k) for k in ("GIT_INDEX_FILE", "GIT_DIR")}
        os.environ["GIT_INDEX_FILE"] = str(self.tmp / "someone-elses-index")
        os.environ["GIT_DIR"] = str(self.tmp / "someone-elses-repo")
        try:
            self.assertEqual(improve.git(self.repo, "status", "--porcelain"), "")
        finally:
            for k, v in saved.items():
                os.environ.pop(k, None) if v is None else os.environ.__setitem__(k, v)
        self.assertFalse((self.tmp / "someone-elses-index").exists())

    def test_new_test_must_run_to_count_as_failing(self):
        # A test that can't even be imported "fails" before the fix for the wrong reason; it proves nothing.
        src = (self.repo / "briefing.py").read_text().splitlines()
        i = next(n for n, l in enumerate(src, 1) if "th = float(cfg.get(\"companion_threshold_base\"" in l)
        new = src[i - 1].replace('0.75))', '0.75)) + 0.12')
        fix = f"--- a/briefing.py\n+++ b/briefing.py\n@@ -{i - 1},3 +{i - 1},3 @@\n {src[i - 2]}\n-{src[i - 1]}\n+{new}\n {src[i]}\n"
        test_src = ["import unittest", "import no_such_module", "class T(unittest.TestCase):",
                    "    def test_x(self):", "        self.assertTrue(True)"]
        tpatch = "--- /dev/null\n+++ b/tests/improve_cases/test_broken.py\n@@ -0,0 +1,%d @@\n" % len(test_src) + "".join("+" + l + "\n" for l in test_src)
        cand = {"kind": "code", "problem": "companion_interrupts", "patch": tpatch + fix, "ok": True, "why": "", "summary": "x",
                "deltas": {}, "root_cause": "ignored guesses fire on weak signals", "test_first": {}}
        prop, why = improve.gate(self.cfg, cand)
        self.assertIsNone(prop)
        self.assertIn("doesn't run", why)


class TestTelemetry(ImproveBase):
    def test_events_logged_locally_without_content(self):
        b.brief_feedback("down", "too long")
        OLL.mode = "ok"
        b.ollama_chat(dict(self.cfg, ollama_url="http://127.0.0.1:9"), "s", "secret text")
        with self.assertRaises(KeyError):
            b.automation_decide("nope", "reset")
        tel = b.telemetry_read()
        kinds = [t["kind"] for t in tel]
        for k in ("briefing", "llm", "automation"):
            self.assertIn(k, kinds)
        self.assertNotIn("secret", json.dumps(tel)); self.assertNotIn("too long", json.dumps(tel))
        self.assertFalse([t for t in tel if t["kind"] == "llm"][0]["ok"])
        with self.assertRaises(ValueError):
            b.brief_feedback("meh")
        m = improve.metrics(self.cfg)
        self.assertEqual(m["briefing"]["down_rate"], 1.0)


class TestObsidianAndThings(ImproveBase):
    def test_vault_wikilinks_frontmatter(self):
        (b.MEM / "people.md").write_text("# People\n\n- Sam: designer, reviews landing page\n- **Priya** (manager)\n")
        (b.MEM / "projects").mkdir(exist_ok=True)
        (b.MEM / "projects" / "landing-page.md").write_text("# Landing page\n")
        day = time.strftime("%Y-%m-%d")
        b.proj_save("landing-page", {"sessions": [{"day": day, "start": time.time(), "minutes": 30, "title": "hero", "src": "#1"}],
                                     "files": {}, "urls": {}, "apps": {}})
        b.add_daily([{"type": "card", "ts": time.time(), "start_ts": time.time(), "end_ts": time.time() + 60, "day": day,
                      "title": "Design review with Sam", "summary": "Figma", "category": "Work"}])
        b.render_daily(day)
        d = (b.MEM / "daily" / f"{day}.md").read_text()
        self.assertTrue(d.startswith("---\ntags: [daily]")); self.assertIn("[[landing-page]]", d); self.assertIn("[[Sam]]", d)
        out = b.vault_sync(self.cfg)
        self.assertIn("vault ok", out)
        self.assertTrue((b.MEM / ".obsidian" / "app.json").exists())
        sam = (b.MEM / "people" / "Sam.md").read_text()
        self.assertIn("tags: [person]", sam); self.assertIn(f"[[{day}]]", sam)
        self.assertTrue((b.MEM / "people" / "Priya.md").exists())
        self.assertIn("[[Sam]]", (b.MEM / "people.md").read_text())
        self.assertTrue((b.MEM / "projects" / "landing-page.md").read_text().startswith("---\ntags: [project]"))
        self.assertTrue((b.MEM / "goals.md").read_text().startswith("---\ntags: [briefing, curated]"))
        # idempotent; the user's own notes in a person file survive
        p = b.MEM / "people" / "Sam.md"
        p.write_text(p.read_text().replace("# Sam\n", "# Sam\nLikes blue.\n"))
        b.vault_sync(self.cfg); b.vault_sync(self.cfg)
        self.assertIn("Likes blue.", p.read_text()); self.assertEqual(p.read_text().count("tags: [person]"), 1)
        self.assertEqual((b.MEM / "goals.md").read_text().count("---\ntags"), 1)

    def test_things_off_by_default_then_dedupe_and_complete(self):
        sent = []
        orig = b.things_open
        b.things_open = lambda url: sent.append(url) or url
        try:
            b.todo_add("Send Sam the pricing copy", "test")
            self.assertEqual(sent, [])
            self.assertIn("skipped", b.things_sync(self.cfg))
            self.write_cfg(things_sync=True, things_list="Work")
            r = b.things_sync(b.load_config())
            self.assertEqual(r["added"], 1)
            self.assertTrue(sent[0].startswith("things:///add?title=Send%20Sam"))
            self.assertIn("list=Work", sent[0]); self.assertIn("briefing-id%3A", sent[0])
            b.todo_add("Book the dentist appointment", "test")  # hook in todos_save pushes it
            self.assertEqual(len(sent), 2)
            self.assertEqual(b.things_sync(b.load_config())["added"], 0)  # deduped
            b.todo_add("Pay BankCo invoice now", "test")  # blocklisted keyword never leaves the Mac
            t = b.todos_load()
            b.todo_set(t[0]["id"], True)
            self.assertEqual(b.jload(b.DATA / "things.json", {})[t[0]["id"]]["done_sent"], True)
            db = b.jload(b.DATA / "things.json", {}); db[t[1]["id"]]["things_id"] = "ABC"; b.jsave(b.DATA / "things.json", db)
            self.write_cfg(things_auth_token="tok")
            b.todo_set(t[1]["id"], True)
            self.assertTrue(sent[-1].startswith("things:///update?id=ABC&auth-token=tok&completed=true"))
        finally:
            b.things_open = orig


if __name__ == "__main__":
    unittest.main()
