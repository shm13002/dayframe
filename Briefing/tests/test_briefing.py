"""Run: python3 -m unittest discover -s tests -v   (stdlib only; no Mac needed)"""
import io, json, os, sqlite3, sys, tempfile, time, unittest, urllib.request, urllib.error, threading, contextlib
import datetime as dt
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent)); sys.path.insert(0, str(HERE))
os.environ.setdefault("BRIEFING_HOME", tempfile.mkdtemp())
os.environ["BRIEFING_IGNORE_OVERRIDES"] = "1"  # tests run against plain defaults, whatever tunables.json says
import briefing as b  # noqa: E402
import mocks  # noqa: E402

OLL = mocks.FakeOllama()

class Base(unittest.TestCase):
    weeks = 6
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        b.set_home(self.tmp / "home")
        self.db = str(self.tmp / "df" / "chunks.sqlite")
        self.ncards = mocks.make_dayflow(self.db, weeks=self.weeks)
        mocks.make_meetily(str(self.tmp / "meetily.sqlite"))
        b.HOME.mkdir(parents=True)
        b.CONFIG_PATH.write_text(json.dumps({
            "model": "m", "ollama_url": OLL.url, "dayflow_db": self.db, "meetily_db": str(self.tmp / "meetily.sqlite"),
            "blocklist": {"apps": [], "sites": [], "keywords": ["BankCo"]}, "checkin_quiet_hours": [0, 0],
            "request_timeout_s": 10, "dashboard_port": 0}))
        OLL.mode = "ok"
        os.environ["BRIEFING_TEST_IDLE"] = "0"
        for k in ("BRIEFING_TEST_ANSWER", "BRIEFING_TEST_RESUME", "BRIEFING_TEST_NORUN"):
            os.environ.pop(k, None)
        self.cfg = b.load_config(); b.mem_init()
    def nightly(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return b.cmd_nightly(self.cfg)

class TestDistill(Base):
    def test_multiweek_distill_all_cards_once(self):
        r = self.nightly()
        st = b.load_state()
        con = sqlite3.connect(self.db)
        mx = con.execute("select max(id) from timeline_cards").fetchone()[0]
        self.assertEqual(st["wm_card_id"], mx, r)
        n_jsonl = sum(len(b.daily_entries(p.name[1:-6])) for p in (b.MEM / "daily").glob(".*.jsonl"))
        live = con.execute("select count(*) from timeline_cards where is_deleted=0 and title not like '%Bank%'").fetchone()[0]
        self.assertEqual(n_jsonl, live + 1)  # + 1 meeting
        self.assertEqual(b.cmd_distill(self.cfg), "nothing new")  # idempotent
    def test_privacy_blocklist_never_stored(self):
        self.nightly()
        for p in b.HOME.rglob("*"):
            if p.is_file() and p.suffix in (".md", ".jsonl", ".json") and p.name != "config.json":
                self.assertNotIn("BankCo", p.read_text(errors="ignore"), p)
    def test_citations_point_to_real_lines(self):
        self.nightly()
        import re
        cites = re.findall(r"\[(\d{4}-\d\d-\d\d)#(\d+)\]", (b.MEM / "goals.md").read_text())
        self.assertTrue(cites)
        for day, ln in cites:
            self.assertIn(int(ln), [e["ln"] for e in b.daily_entries(day)])
    def test_unicode_roundtrip_and_slug(self):
        self.nightly()
        md = "".join(p.read_text() for p in (b.MEM / "daily").glob("*.md"))
        self.assertIn("日本語", md); self.assertIn("שלום", md); self.assertIn("☕", md)
        self.assertTrue((b.MEM / "projects" / "caf-app.md").exists() or any("caf" in p.name for p in (b.MEM / "projects").iterdir()))
        self.assertEqual(b.slugify("☕☕"), "misc")
    def test_meeting_and_todos(self):
        self.nightly()
        texts = [t["text"] for t in b.todos_load()]
        self.assertIn("Send pricing sheet to Sam", texts)
        self.assertTrue(any("mobile nav" in t.lower() for t in texts))
        self.assertEqual(len([t for t in texts if "mobile nav" in t.lower()]), 1, texts)  # dedupe
    def test_dayflow_down_is_graceful(self):
        os.remove(self.db)
        self.assertIn("distilled 0 cards", b.cmd_distill(self.cfg))  # only the Meetily meeting
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(b.cmd_brief(self.cfg, force=True, interactive=False)[:5], "WHERE")
    def test_schema_changed(self):
        con = sqlite3.connect(self.db); con.execute("alter table timeline_cards rename column summary to summ"); con.commit(); con.close()
        cards, note = b.fetch_new_cards(self.cfg, 0, 10)
        self.assertEqual(cards, []); self.assertIn("schema", note)

class TestEmptyDB(Base):
    weeks = 0
    def test_empty_everything(self):
        self.assertEqual(b.cmd_distill(self.cfg), "nothing new") if not b.meetily_new(self.cfg, "")[0] else None
        self.assertEqual(b.mine_patterns(self.cfg), [])
        self.assertIn("I don't have", b.cmd_ask(self.cfg, "what did I do?"))
        self.assertEqual(b.focus_stats(self.cfg)["total_minutes"], 0)
        b.reindex(self.cfg)
        self.assertEqual(b.search("anything", cfg=self.cfg), [])
        self.assertIsNone(b.resume_targets(self.cfg))
        st = b.dashboard_state(self.cfg)
        self.assertEqual(st["timeline"], [])

class TestModelFailures(Base):
    def test_malformed_json_queues_then_recovers(self):
        OLL.mode = "garbage"
        r = b.cmd_distill(self.cfg)
        self.assertIn("unparseable", r)
        self.assertTrue((b.MEM / ".pending_curation.txt").exists())
        self.assertGreater(len(b.daily_entries(dt.date.today().isoformat())) + len(list((b.MEM / "daily").glob(".*"))), 0)  # raw log kept
        OLL.mode = "ok"
        con = sqlite3.connect(self.db); con.execute("insert into timeline_cards(batch_id,start,end,start_ts,end_ts,day,title,summary,category) values(1,'','',?,?,?,?,?,?)",
                                                    (int(time.time()) - 600, int(time.time()) - 60, dt.date.today().isoformat(), "New thing", "x", "Work")); con.commit(); con.close()
        b.cmd_distill(self.cfg)
        self.assertFalse((b.MEM / ".pending_curation.txt").exists())
    def test_fenced_json_parsed(self):
        OLL.mode = "fenced"
        self.assertIn("updated", b.cmd_distill(self.cfg))
    def test_parse_json_edge(self):
        self.assertIsNone(b.parse_json("no braces"))
        self.assertEqual(b.parse_json('```json\n{"a":1}\n```'), {"a": 1})
        self.assertEqual(b.parse_json('```\n{"a":"ü"}\n```'), {"a": "ü"})
    def test_empty_model_reply_does_not_wipe_files(self):
        self.nightly()
        before = (b.MEM / "goals.md").read_text()
        OLL.mode = "empty"
        b.merge_file(self.cfg, b.MEM / "goals.md", "goals", ["x"])
        self.assertEqual((b.MEM / "goals.md").read_text(), before)
    def test_ollama_down(self):
        cfg = dict(self.cfg, ollama_url="http://127.0.0.1:9", request_timeout_s=2)
        with contextlib.redirect_stdout(io.StringIO()):
            txt = b.cmd_brief(cfg, force=True, interactive=False)
        self.assertIn("Local AI unavailable", txt)
        self.assertIn("unavailable", b.cmd_ask(cfg, "hero"))
        self.assertIn("model unavailable", b.predict_next(cfg, "app_switch")["gated"])
        self.assertIn("error", b.automation_draft(cfg, "nope"))
    def test_bad_embeddings_fall_back_to_fts(self):
        self.nightly()
        OLL.mode = "garbage"
        self.assertTrue(b.search("hero", cfg=self.cfg))

class TestHuge(Base):
    weeks = 1
    def test_huge_day(self):
        day = dt.date.today().isoformat(); t = time.time() - 86000
        b.add_daily([{"type": "card", "ts": t + i, "start_ts": t + i * 10, "end_ts": t + i * 10 + 9, "day": day,
                      "title": f"Card {i} ✓", "summary": "x" * 400, "category": "Work"} for i in range(5000)])
        t0 = time.time(); b.reindex(self.cfg); self.assertLess(time.time() - t0, 30)
        ctx = b.build_context(self.cfg, [], None, None, "")
        self.assertLess(len(ctx), 40000)
        b.cmd_ask(self.cfg, f"what did I do {day}?")
        self.assertLess(len(OLL.calls[-1][1]), 30000)
        st = b.dashboard_state(self.cfg)
        self.assertLessEqual(len(st["timeline"]), b.DASH_TIMELINE_MAX)

class TestForget(Base):
    def test_forget_range(self):
        self.nightly()
        day = sorted(p.stem for p in (b.MEM / "daily").glob("2*.md"))[0]
        r = b.cmd_forget(self.cfg, day, day)
        self.assertIn("forgot", r)
        self.assertFalse((b.MEM / "daily" / f"{day}.md").exists())
        hits = [p for p in b.MEM.rglob("*.md") if day in p.read_text()]
        self.assertEqual(hits, [])
        self.assertEqual(list((b.MEM / ".backups").iterdir()), [])
        self.assertIn("before", b.cmd_forget(self.cfg, "2026-10-05", "2026-10-01"))
    def test_forget_bad_date(self):
        with self.assertRaises(ValueError):
            b.cmd_forget(self.cfg, "yesterday", "x")

class TestAutomations(Base):
    def test_mine_rank_and_lifecycle(self):
        self.nightly()
        items = b.automations_refresh(self.cfg)
        self.assertTrue(items)
        self.assertEqual(items, sorted(items, key=lambda a: -a["minutes_saved_week"]))
        self.assertFalse(any("YouTube" in a["label"] and a["kind"] == "routine" for a in items))
        self.assertFalse(any("BankCo" in json.dumps(a) for a in items))
        aid = items[0]["id"]
        self.assertFalse(b.automation_run(self.cfg, aid, True)["ok"])
        d = b.automation_draft(self.cfg, aid); self.assertTrue(Path(d["file"]).exists())
        self.assertTrue(b.automation_dryrun(self.cfg, aid)["ok"])
        b.automation_decide(aid, "approve")
        self.assertFalse(b.automation_run(self.cfg, aid, False)["ok"])
        os.environ["BRIEFING_TEST_NORUN"] = "1"
        self.assertTrue(b.automation_run(self.cfg, aid, True)["ok"])
        Path(d["file"]).write_text(Path(d["file"]).read_text() + "\nsudo rm -rf /tmp/x\n")
        self.assertIn("changed", b.automation_run(self.cfg, aid, True)["log"])
        self.assertFalse(b.automation_dryrun(self.cfg, aid)["ok"])
        b.automation_decide(aid, "reject")
        ev = [h["event"] for h in next(a for a in b.automations_list() if a["id"] == aid)["history"]]
        self.assertEqual(ev[0], "drafted"); self.assertEqual(ev[-1], "rejected")
    def test_draft_malformed(self):
        self.nightly(); aid = b.automations_refresh(self.cfg)[0]["id"]
        OLL.mode = "garbage"
        self.assertIn("error", b.automation_draft(self.cfg, aid))

class TestNextMove(Base):
    def test_gates_validation_learning(self):
        self.nightly()
        os.environ["BRIEFING_TEST_IDLE"] = "900"; self.assertEqual(b.predict_next(self.cfg, "app_switch")["gated"], "user idle")
        os.environ["BRIEFING_TEST_IDLE"] = "0"
        p = b.predict_next(self.cfg, "app_switch", app="Figma")
        self.assertEqual([a["target"] for a in p["actions"]], ["Cursor", "Ping Sam"])  # hallucinated app dropped
        self.assertIn("cooldown", b.predict_next(self.cfg, "app_switch")["gated"])
        b.nm_feedback(self.cfg, p["id"], "dismiss")
        self.assertIn("20 min", b.predict_next(self.cfg, "app_switch")["gated"])
        n = len(OLL.calls)
        d = b.jload(b.NM_DB, {}); d.update(last_shown=0, dismiss_streak=0, last_attempt=time.time()); b.jsave(b.NM_DB, d)
        self.assertEqual(b.predict_next(self.cfg, "tick")["gated"], "rate limited")
        self.assertEqual(len(OLL.calls), n)  # no model call while rate limited
        p = b.predict_next(self.cfg, "hotkey", force=True)
        self.assertEqual(b.nm_feedback(self.cfg, p["id"], "accept", 1)["result"], "added")
        self.assertIn("error", b.nm_feedback(self.cfg, p["id"], "accept", 0))
        self.assertIn("error", b.nm_feedback(self.cfg, "x", "accept", 99))
    def test_malformed_model(self):
        OLL.mode = "garbage"
        self.assertIsNone(b.predict_next(self.cfg, "app_switch")["intent"])

class TestCoachReportCleanup(Base):
    def test_coach_and_report(self):
        self.nightly(); now = time.time()
        b.add_daily([{"type": "card", "ts": now - 1700, "start_ts": now - 1700, "end_ts": now - 60, "title": "YouTube",
                      "category": "Distraction", "day": dt.date.today().isoformat()}])
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertTrue(b.cmd_coach(self.cfg).startswith("nudged"))
            self.assertEqual(b.cmd_coach(self.cfg), "cooldown")
            self.assertTrue(b.cmd_report(self.cfg).startswith("report"))
        s = b.focus_stats(self.cfg)
        self.assertGreater(s["total_minutes"], 0); self.assertEqual(len(s["heat"]), 7)
    def test_cleanup_only_old_processed(self):
        rec = Path(self.db).parent / "recordings"; rec.mkdir()
        con = sqlite3.connect(self.db)
        old, new, unref = rec / "a.mp4", rec / "b.mp4", rec / "c.mp4"
        for i, f in enumerate((old, new, unref), 1):
            f.write_bytes(b"x" * 100)
        (rec / "x.sqlite").write_bytes(b"db")
        for f in (old, rec / "x.sqlite"):
            os.utime(f, (time.time() - 3 * 86400,) * 2)
        con.execute("insert into screenshots(id,captured_at,file_path) values(1,0,?),(2,0,?)", (str(old), str(new)))
        con.execute("insert into batch_screenshots values(1,1),(1,2)"); con.commit(); con.close()
        self.nightly()
        c, _, _ = b.deletable_recordings(self.cfg)
        self.assertEqual([str(p) for p, _, _ in c], [str(old.resolve())])
        b.cmd_cleanup(dict(self.cfg, cleanup_enabled=True))
        self.assertFalse(old.exists()); self.assertTrue(new.exists() and unref.exists() and (rec / "x.sqlite").exists())
        self.assertTrue(Path(self.db).exists())

class TestDebriefWakeCli(Base):
    def test_cli_smoke(self):
        os.environ["BRIEFING_TEST_ANSWER"] = "Fine. I need to rewrite the FAQ"
        os.environ["BRIEFING_TEST_RESUME"] = "yes"
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            for cmd in (["nightly"], ["status"], ["ask", "hero.css?"], ["weekly"], ["report"], ["debrief"], ["coach"],
                        ["context", "--json"], ["todo"], ["todo", "Buy milk"], ["automations"], ["next-move", "--force"],
                        ["resume"], ["wake"], ["checkin"], ["reindex"], ["cleanup"], ["brief", "--force"],
                        ["forget", "--from", "2020-01-01", "--to", "2020-01-02"]):
                b.main(cmd)
        self.assertIn("Rewrite the FAQ", [t["text"] for t in b.todos_load()])
        self.assertIn("resumed", out.getvalue())

    def test_commands_never_touch_the_real_mac(self):
        # `resume` opens links and activates apps, and `brief` shows a dialog. In tests they must be
        # recorded by run_on_mac, never run: tests/mocks.py sets BRIEFING_NO_DESKTOP=1.
        os.environ["BRIEFING_TEST_RESUME"] = "yes"
        self.nightly()
        b.DESKTOP_CALLS.clear()
        orig_mac = b.is_mac
        b.is_mac = lambda: True
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                b.main(["resume"])
                b.main(["brief", "--force"])
        finally:
            b.is_mac = orig_mac
        calls = [" ".join(c) for c in b.DESKTOP_CALLS]
        self.assertTrue(any(c.startswith("open ") and "github.com/me/site/pull/12" in c for c in calls), calls)
        self.assertTrue(any("Where you left off" in c for c in calls), calls)

class TestServer(Base):
    def setUp(self):
        super().setUp()
        self.nightly()
        import socketserver, http.server
        class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
            daemon_threads = True
        self.srv = S(("127.0.0.1", 0), b.make_handler({"cfg": self.cfg}))
        self.port = self.srv.server_address[1]
        self.cfg["dashboard_port"] = self.port
        b.CONFIG_PATH.write_text(json.dumps(dict(json.loads(b.CONFIG_PATH.read_text()), dashboard_port=self.port)))
        self.srv.RequestHandlerClass = b.make_handler({"cfg": self.cfg})
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
    def tearDown(self):
        self.srv.shutdown(); self.srv.server_close()
    def req(self, path, body=None, headers=None, raw=None):
        h = {"Content-Type": "application/json"} if body is not None else {}
        h.update(headers or {})
        r = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", data=raw if raw is not None else (json.dumps(body).encode() if body is not None else None), headers=h)
        try:
            with urllib.request.urlopen(r, timeout=20) as resp:
                return resp.status, json.loads(resp.read() or b"null") if resp.headers.get_content_type() == "application/json" else resp.read()
        except urllib.error.HTTPError as e:
            return e.code, None
    def test_endpoints_and_security(self):
        self.assertEqual(self.req("/")[0], 200)
        s, st = self.req("/api/state"); self.assertEqual(s, 200); self.assertIn("todos", st)
        self.assertEqual(self.req("/api/state", headers={"Host": "evil.com"})[0], 403)
        self.assertEqual(self.req("/api/todo", {"add": "x"}, headers={"Origin": "http://evil.com"})[0], 403)
        self.assertEqual(self.req("/api/todo", raw=b"a=b", headers={"Content-Type": "application/x-www-form-urlencoded"})[0], 403)
        self.assertEqual(self.req("/api/day/../../etc")[0], 400)
        self.assertEqual(self.req("/api/nope")[0], 404)
        self.assertEqual(self.req("/api/forget", {"from": "bad", "to": "bad"})[0], 400)
        self.assertEqual(self.req("/api/automations/draft", {})[0], 400)
        self.assertEqual(self.req("/api/settings", {"model": "m2", "ollama_url": "http://evil"})[0], 200)
        c = json.loads(b.CONFIG_PATH.read_text()); self.assertEqual(c["model"], "m2"); self.assertNotEqual(c["ollama_url"], "http://evil")
        self.assertEqual(self.req("/api/ask", {"q": "hero.css ✓"})[0], 200)
        s, r = self.req("/api/automations/run", {"id": "x"}); self.assertFalse(r["ok"])
        s, r = self.req("/api/automations/refresh", {}); self.assertTrue(r["items"])
        s, r = self.req("/api/next-move?trigger=app_switch&app=Figma"); self.assertEqual(s, 200)
        self.assertEqual(self.req("/api/context")[0], 200)
        s, r = self.req("/api/todo", {"add": "Ünïcødé task ✓"}); self.assertIn("Ünïcødé task ✓", [t["text"] for t in r["todos"]])
        self.assertEqual(self.req("/api/todo", raw=b"{bad json", headers={"Content-Type": "application/json"})[0], 400)

if __name__ == "__main__":
    unittest.main()

class TestRound3Gaps(Base):
    def test_project_autopilot_formats_hours(self):
        self.nightly()
        txt = (b.MEM / "projects" / "landing-page.md").read_text()
        self.assertRegex(txt, r"Total tracked:\*\* \d+h \d\dm")
    def test_dashboard_state_reports_total(self):
        day = dt.date.today().isoformat(); t = time.time() - 50000
        b.add_daily([{"type": "card", "ts": t + i, "start_ts": t + i, "end_ts": t + i + 5, "day": day, "title": "x", "category": "Work"} for i in range(450)])
        st = b.dashboard_state(self.cfg)
        self.assertEqual(st["timeline_total"], 450); self.assertEqual(len(st["timeline"]), 400)
    def test_unicode_automation_title_and_blocklist_in_mining(self):
        self.nightly()
        OLL.mode = "ok"
        aid = next(a["id"] for a in b.automations_refresh(self.cfg) if "Xcode" in json.dumps(a))
        d = b.automation_draft(self.cfg, aid, hint="日本語 ✓")
        self.assertTrue(Path(d["file"]).exists())
        self.assertTrue(Path(d["file"]).read_text().startswith("#!/bin/bash"))
    def test_set_home_isolates(self):
        other = self.tmp / "other"; b.set_home(other); b.mem_init()
        self.assertTrue((other / "memory" / "goals.md").exists())
        self.assertEqual(b.NM_DB, other / "memory" / "data" / "nextmove.json")

STUCK = {"dwell_s": 600, "scroll_reversals": 7, "rereads": 3, "search_switches": 2, "idle_s": 60, "present": True,
         "typing_cpm": 2, "time_on_task_s": 1500}
SCREENS = {
    "study": dict(app="Preview", window_title="calc_pset3.pdf", screen_text="Problem 4. Evaluate ∫ (x² + 3x) dx.\nStep 2: split the integral\nStep 3: ?"),
    "coding": dict(app="Cursor", window_title="loader.py — app", screen_text="Traceback (most recent call last):\n  File loader.py\nTypeError: 'NoneType' object is not iterable\ndef load(path):"),
    "spreadsheets": dict(app="Microsoft Excel", window_title="budget.xlsx", screen_text="C4 #REF! =VLOOKUP(A2,Sheet2!A:B,2,0)"),
    "writing": dict(app="Pages", window_title="Essay draft", screen_text="Introduction\nDear committee, I am writing to..."),
    "admin": dict(app="System Settings", window_title="Privacy & Security", screen_text="Privacy & Security\nScreen Recording\nAllow the apps below"),
    "unknown": dict(app="SomeTool", window_title="Untitled", screen_text="Widgets and knobs"),
    "shopping": dict(app="Safari", window_title="Laptop stand - Amazon", url="https://www.amazon.com/dp/1", screen_text="Add to Cart $39.99 4.5 stars 2,301 reviews"),
}

class TestCompanion(Base):
    def ant(self, mode, **kw):
        sig = dict(STUCK, **SCREENS[mode]); sig.update(kw)
        return b.anticipate(self.cfg, sig)

    def test_mode_detection(self):
        for mode, scr in SCREENS.items():
            self.assertEqual(b.detect_mode(self.cfg, scr)[0], mode, mode)
        self.assertEqual(b.detect_subject("study", SCREENS["study"]), "calculus")
        self.assertEqual(b.detect_subject("coding", SCREENS["coding"]), "Python")
        self.assertNotEqual(b.detect_mode(dict(self.cfg, companion_study_detection=False), SCREENS["study"])[0], "study")

    def test_stuck_score_and_gate(self):
        calm = b.anticipate(self.cfg, dict(SCREENS["coding"], dwell_s=20, typing_cpm=200))
        self.assertFalse(calm["stuck"])
        s, reasons = b.stuck_score(self.cfg, dict(STUCK, **SCREENS["coding"]), "coding")
        self.assertGreater(s, 0.8); self.assertTrue(any("search" in r for r in reasons))
        lo = b.anticipate(dict(self.cfg, companion_sensitivity=0.0), dict(SCREENS["writing"], dwell_s=200, typing_cpm=5))
        hi = b.anticipate(dict(self.cfg, companion_sensitivity=1.0), dict(SCREENS["writing"], dwell_s=200, typing_cpm=5))
        self.assertGreater(lo["threshold"], hi["threshold"])

    def test_two_phase_and_per_mode_questions(self):
        sig = dict(STUCK, **{k: v for k, v in SCREENS["coding"].items() if k != "screen_text"})
        r = b.anticipate(self.cfg, sig)
        self.assertTrue(r["need_text"]); self.assertNotIn("questions", r)
        expect = {"study": ("hints", "Step 3"), "coding": ("fix", "TypeError"), "spreadsheets": ("formula", "#REF!"),
                  "writing": ("rewrite", "Introduction"), "admin": ("steps", "Privacy & Security"), "unknown": ("steps", "")}
        for mode, (amode, anchor) in expect.items():
            r = self.ant(mode)
            self.assertEqual((r["mode"], r["answer_mode"]), (mode, amode), r)
            self.assertEqual(r["questions"][0]["anchor"], anchor)
            self.assertEqual(len(r["questions"]), 2)  # empty question dropped
            self.assertEqual(r["questions"][1]["anchor"], "")  # hallucinated anchor removed
        self.assertIn("cooldown", self.ant("coding")["gated"])

    def test_vision_path_and_fallback(self):
        r = self.ant("unknown", screen_text="", image_b64="aGVsbG8=")
        self.assertEqual(OLL.last_images, ["aGVsbG8="]); self.assertEqual(OLL.last_model, "qwen2.5vl:7b")
        OLL.mode = "garbage"
        r = self.ant("spreadsheets")
        self.assertTrue(r["fallback"]); self.assertEqual(r["questions"][0]["text"], "What formula do I need here?")

    def test_privacy(self):
        r = b.anticipate(self.cfg, dict(STUCK, app="Safari", window_title="BankCo login", screen_text="x"))
        self.assertEqual(r["gated"], "blocked")
        r = self.ant("writing", screen_text="my BankCo PIN")
        self.assertEqual(r.get("gated"), "blocked")

    def stream(self, body):
        return list(b.answer_stream(self.cfg, body))

    def test_hint_ladder_and_anchor(self):
        r = self.ant("study"); q = r["best"]
        texts = []
        for lvl in (1, 2, 3):
            out = self.stream({"id": r["id"], "question": q, "level": lvl, "previous": texts})
            text = "".join(o.get("delta", "") for o in out)
            texts.append(text)
            self.assertEqual(out[-1]["more"], lvl < 3)
            self.assertNotIn("ANCHOR", text)
        self.assertIn("rule", texts[0]); self.assertIn("power rule", texts[1]); self.assertIn("x³/3", texts[2])
        self.assertNotIn("x³/3", texts[0] + texts[1])  # hints never give it away
        self.assertIn({"anchor": "Step 3"}, out)
        self.assertIn("Earlier hints", OLL.calls[-1][1])

    def test_answer_styles_per_mode(self):
        r = self.ant("coding"); out = self.stream({"id": r["id"], "question": r["best"]})
        self.assertIn("```python", "".join(o.get("delta", "") for o in out))
        r = self.ant("spreadsheets"); out = self.stream({"id": r["id"], "question": r["best"]})
        self.assertIn("XLOOKUP", "".join(o.get("delta", "") for o in out))
        r = self.ant("admin"); out = self.stream({"id": r["id"], "question": r["best"]})
        self.assertIn({"anchor": "Privacy & Security"}, out)
        r = self.ant("shopping"); out = self.stream({"id": r["id"], "question": "best?"})
        self.assertFalse(any("anchor" in o for o in out))  # anchor not on screen → no pointer
        self.assertEqual(self.stream({"question": ""}), [{"error": "empty question"}])
        OLL.mode = "garbage"
        self.assertIn("error", self.stream({"question": "x"})[-1])

    def test_learning_loop(self):
        # 1) chosen → hit; 2) edited (small) → hit with diff; 3) typed own → miss but becomes a few-shot example; 4) ignored
        r1 = self.ant("coding"); self.assertTrue(b.companion_feedback(self.cfg, {"id": r1["id"], "outcome": "chosen", "index": 0})["hit"])
        b.comp_save(dict(b.comp_load(), last_by_window={}))
        r2 = self.ant("coding")
        fb = b.companion_feedback(self.cfg, {"id": r2["id"], "outcome": "chosen", "index": 0,
                                             "final_text": "Why is this raising TypeError: 'NoneType' object is not iterable in load()?"})
        self.assertTrue(fb["hit"]); self.assertIn("+load()?", fb["diff"])
        self.assertIn("error", b.companion_feedback(self.cfg, {"id": r2["id"], "outcome": "chosen"}))  # no double rating
        b.comp_save(dict(b.comp_load(), last_by_window={}))
        r3 = self.ant("coding")
        self.assertFalse(b.companion_feedback(self.cfg, {"id": r3["id"], "outcome": "typed", "final_text": "How do I mock open() in pytest?"})["hit"])
        b.comp_save(dict(b.comp_load(), last_by_window={}))
        r4 = self.ant("coding"); b.companion_feedback(self.cfg, {"id": r4["id"], "outcome": "ignored"})
        b.comp_save(dict(b.comp_load(), last_by_window={}))
        self.ant("coding")
        prompt = OLL.calls[-1][1]
        self.assertIn("How do I mock open() in pytest?", prompt)  # few-shot from what they really asked
        st = b.companion_stats(self.cfg)
        self.assertEqual(st["hit_rate_week"], 50); self.assertEqual(st["by_mode"]["coding"]["n"], 4)
        self.assertEqual(st["days"][-1]["n"], 4)
        self.assertEqual(sum(st["outcomes"].values()), 4)
        self.assertTrue(st["styles"]["coding"].startswith("This user's questions"))

    def test_few_shot_isolation_per_mode_and_app(self):
        r = self.ant("study"); b.companion_feedback(self.cfg, {"id": r["id"], "outcome": "typed", "final_text": "Why does the constant C appear?"})
        b.comp_save(dict(b.comp_load(), last_by_window={}))
        self.ant("coding")
        self.assertNotIn("constant C", OLL.calls[-1][1])  # study examples don't leak into coding
        db = b.comp_load()
        self.assertEqual([e["final"] for e in b.few_shots(db, "study", "Skim")], ["Why does the constant C appear?"])  # mode fallback

    def test_auto_ignore_and_learned_backoff(self):
        r = self.ant("writing")
        db = b.comp_load(); db["pending"][r["id"]]["ts"] -= 400; db["last_by_window"] = {}; b.comp_save(db)
        self.ant("writing")
        self.assertEqual(b.comp_load()["events"][-1]["outcome"], "ignored")
        db = b.comp_load(); base = b.mode_threshold(self.cfg, db, "writing")
        for _ in range(7):
            db["events"].append({"ts": int(time.time()), "mode": "writing", "outcome": "dismissed", "hit": False})
        self.assertGreater(b.mode_threshold(self.cfg, db, "writing"), base)

    def test_study_sessions(self):
        for i in range(3):
            r = self.ant("study"); b.companion_feedback(self.cfg, {"id": r["id"], "outcome": "chosen", "index": 0})
            b.comp_save(dict(b.comp_load(), last_by_window={}))
        ss = b.companion_stats(self.cfg)["study_sessions"]
        self.assertEqual(len(ss), 1); self.assertEqual(ss[0]["questions"], 3); self.assertEqual(ss[0]["subject"], "calculus")

class TestCompanionHTTP(TestServer):
    def test_endpoints_and_security(self):  # override parent's test: companion endpoints only
        s, r = self.req("/api/anticipate", dict(STUCK, **SCREENS["coding"]))
        self.assertEqual(s, 200); self.assertTrue(r["questions"])
        raw = urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{self.port}/api/answer",
              data=json.dumps({"id": r["id"], "question": r["best"]}).encode(), headers={"Content-Type": "application/json"}), timeout=20)
        self.assertEqual(raw.headers.get_content_type(), "application/x-ndjson")
        lines = [json.loads(l) for l in raw.read().decode().splitlines()]
        self.assertTrue(lines[0]["start"]); self.assertTrue(lines[-1]["done"])
        self.assertEqual(self.req("/api/answer", {"question": "x"}, headers={"Origin": "http://evil.com"})[0], 403)
        s, fb = self.req("/api/companion/feedback", {"id": r["id"], "outcome": "chosen", "index": 0}); self.assertTrue(fb["hit"])
        s, st = self.req("/api/companion"); self.assertEqual(st["hit_rate_week"], 100)
        s, fb = self.req("/api/companion/feedback", {"id": "x", "outcome": "bogus"}); self.assertIn("error", fb)
