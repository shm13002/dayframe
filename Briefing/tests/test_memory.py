"""Two clocks, provenance, conflicts, bad-memory repair, facts-vs-processes split, redaction, retro."""
import datetime as dt, json, os, sys, tempfile, time, unittest
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent)); sys.path.insert(0, str(HERE))
os.environ.setdefault("BRIEFING_HOME", tempfile.mkdtemp())
os.environ["BRIEFING_IGNORE_OVERRIDES"] = "1"
import briefing as b  # noqa: E402
import improve  # noqa: E402
import mocks  # noqa: E402

OLL = mocks.FakeOllama()
TODAY = dt.date.today()

class MemBase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        b.set_home(self.tmp / "home"); b.HOME.mkdir(parents=True)
        b.CONFIG_PATH.write_text(json.dumps({"model": "m", "ollama_url": OLL.url, "request_timeout_s": 10,
                                             "dayflow_db": str(self.tmp / "none.sqlite"), "meetily_db": str(self.tmp / "none2.sqlite"),
                                             "blocklist": {"apps": [], "sites": [], "keywords": ["BankCo"]}, "embeddings": False}))
        self.cfg = b.load_config(); b.mem_init(); b.todos_save([])
        OLL.mode = "ok"
        os.environ["BRIEFING_TEST_NORUN"] = "1"

    def log(self, day, title, summary=""):
        b.add_daily([{"type": "card", "ts": time.time(), "start_ts": time.time(), "end_ts": time.time() + 60, "day": day,
                      "title": title, "summary": summary, "category": "Work"}])
        return f"{day}#{len(b.daily_entries(day))}"

    def fact(self, kind, text):
        return next(f for f in b.facts_db()["facts"] if f["kind"] == kind and b.strip_cites(f["text"]) == text)


class TestConflictRule(unittest.TestCase):
    def test_one_word_choice_swap_is_a_conflict_not_a_duplicate(self):
        self.assertTrue(b.facts_conflict("Hero uses the blue CTA chosen with Sam", "Hero uses the green CTA chosen with Sam"))
        self.assertFalse(b.facts_conflict("Hero uses the blue CTA chosen with Sam", "Hero uses the blue CTA, chosen with Sam"))
        self.assertFalse(b.facts_conflict("Prefers dark mode", "Prefers dark mode."))


class TestTwoClocksAndProvenance(MemBase):
    def test_classification_and_provenance(self):
        c1 = self.log(TODAY.isoformat(), "Spanish lesson")
        c2 = self.log(TODAY.isoformat(), "Pricing page")
        b.ingest_facts(self.cfg, "goals", [f"Learn Spanish to B2 level [{c1}]", f"Ship the pricing page by Friday [{c2}]"])
        b.ingest_facts(self.cfg, "profile", ["Prefers dark mode in every editor [1999-01-01#9]"])
        stable, changing = self.fact("goals", "Learn Spanish to B2 level"), self.fact("goals", "Ship the pricing page by Friday")
        self.assertEqual((stable["clock"], changing["clock"]), ("stable", "changing"))
        self.assertEqual(changing["sources"][0], {"cite": c2, "log": f"daily/.{TODAY}.jsonl", "line": int(c2.split("#")[1]), "ok": True})
        self.assertEqual(changing["review"], (TODAY + dt.timedelta(days=7)).isoformat())
        self.assertEqual(stable["review"], (TODAY + dt.timedelta(days=120)).isoformat())
        self.assertEqual(changing["created"], TODAY.isoformat()); self.assertGreater(changing["confidence"], 0.6)
        bogus = self.fact("profile", "Prefers dark mode in every editor")
        self.assertFalse(bogus["sources"][0]["ok"]); self.assertLess(bogus["confidence"], 0.5)  # citation doesn't resolve

    def test_stale_fact_is_marked_and_not_used_silently(self):
        old = (TODAY - dt.timedelta(days=20)).isoformat()
        c = self.log(old, "Hero banner redesign", "waiting on Dana for copy")
        b.ingest_facts(self.cfg, "goals", [f"Hero banner status: waiting on Dana for copy [{c}]"])
        (b.MEM / "goals.md").write_text(f"# Goals\n\n- Hero banner status: waiting on Dana for copy [{c}]\n- Learn Spanish\n")
        db = b.facts_db(); db["facts"][0]["review"] = (TODAY - dt.timedelta(days=1)).isoformat(); b.facts_save(db)
        self.log(TODAY.isoformat(), "Email triage", "inbox zero")  # recent logs don't mention it
        _db, active, stale = b.facts_for_use(self.cfg)
        self.assertEqual([f["status"] for f in stale], ["stale"]); self.assertEqual(active, [])
        ctx = b.build_context(self.cfg, [], None, None, "", (active, stale))
        verified = ctx.split("## STALE")[0]
        self.assertNotIn("waiting on Dana", verified)  # stripped from goals.md view and the verified list
        self.assertIn("Learn Spanish", verified)
        self.assertIn("STALE or disputed", ctx); self.assertIn("waiting on Dana", ctx.split("## STALE")[1])
        out = b.cmd_brief(self.cfg, force=True, interactive=False)
        self.assertIn("out of date and were not used", out)
        b.confirm_fact(self.cfg, stale[0]["id"])
        self.assertEqual(b.facts_for_use(self.cfg)[1][0]["status"], "active")

    def test_due_fact_refreshed_by_recent_evidence(self):
        old = (TODAY - dt.timedelta(days=10)).isoformat()
        c = self.log(old, "Pricing page")
        b.ingest_facts(self.cfg, "project:pricing", [f"Pricing page copy in review with Sam [{c}]"])
        db = b.facts_db(); db["facts"][0]["review"] = old; b.facts_save(db)
        c2 = self.log(TODAY.isoformat(), "Pricing page copy review with Sam")
        _db, active, stale = b.facts_for_use(self.cfg)
        self.assertEqual(stale, []); self.assertIn(c2, [x["cite"] for x in active[0]["sources"]])


class TestConflicts(MemBase):
    def test_conflicting_correction_recorded_not_overwritten(self):
        c1 = self.log(TODAY.isoformat(), "Launch planning")
        b.ingest_facts(self.cfg, "goals", [f"Launch date is Friday [{c1}]"])
        f = self.fact("goals", "Launch date is Friday")
        (b.MEM / "goals.md").write_text(f"# Goals\n\n- Launch date is Friday [{c1}]\n")
        r = b.forget_fact(self.cfg, f["id"], confirm=True, replacement="Launch date is Monday")  # the user corrects it
        self.assertEqual(r["status"], "corrected")
        self.assertIn("Launch date is Monday", (b.MEM / "goals.md").read_text())
        self.assertNotIn("Friday", (b.MEM / "goals.md").read_text())
        c2 = self.log(TODAY.isoformat(), "Launch")  # later activity repeats the old claim
        keep = b.ingest_facts(self.cfg, "goals", [f"Launch date is Friday [{c2}]"])
        self.assertEqual(keep, [])  # not merged into goals.md
        conf = b.facts_db()["conflicts"]
        self.assertEqual(len(conf), 1); self.assertEqual(conf[0]["old_text"], "Launch date is Monday")
        self.assertEqual(self.fact("goals", "Launch date is Monday")["status"], "active")  # untouched
        out = b.cmd_brief(self.cfg, force=True, interactive=False)
        self.assertIn("Question for you", out); self.assertIn("Launch date is Monday", out)
        self.assertEqual(len(b.memory_overview(self.cfg)["conflicts"]), 1)
        b.ingest_facts(self.cfg, "goals", [f"Launch date is Friday [{c2}]"])
        self.assertEqual(len(b.facts_db()["conflicts"]), 1)  # same question isn't asked twice
        b.resolve_conflict(self.cfg, conf[0]["id"], "keep")
        self.assertEqual(b.memory_overview(self.cfg)["conflicts"], [])
        self.assertEqual(self.fact("goals", "Launch date is Monday")["status"], "active")
        with self.assertRaises(KeyError):
            b.resolve_conflict(self.cfg, conf[0]["id"], "new")

    def test_new_answer_wins_when_user_says_so(self):
        c1, c2 = self.log(TODAY.isoformat(), "a"), self.log(TODAY.isoformat(), "b")
        b.ingest_facts(self.cfg, "goals", [f"Newsletter goes out every 2 weeks [{c1}]"])
        b.ingest_facts(self.cfg, "goals", [f"Newsletter goes out every 4 weeks [{c2}]"])
        cid = b.facts_db()["conflicts"][0]["id"]
        b.resolve_conflict(self.cfg, cid, "new")
        self.assertEqual(self.fact("goals", "Newsletter goes out every 4 weeks")["status"], "active")
        self.assertEqual(self.fact("goals", "Newsletter goes out every 2 weeks")["status"], "corrected")


class TestBadMemoryRepair(MemBase):
    def test_bad_memory_traced_and_removed(self):
        c = self.log(TODAY.isoformat(), "Call with Priya")
        loop = f"Send Priya the signed NDA [{c}]"
        b.ingest_facts(self.cfg, "open_loop", [loop])
        f = self.fact("open_loop", "Send Priya the signed NDA")
        b.todo_add("Send Priya the signed NDA", "ai", fact_id=f["id"], sources=[c])
        b.todo_add("Unrelated chore", "cli")
        b.cmd_brief(self.cfg, force=True, interactive=False)
        tr = b.fact_trace(f["id"])
        self.assertEqual(len(tr["briefings"]), 1); self.assertEqual([t["text"] for t in tr["todos"]], ["Send Priya the signed NDA"])
        prev = b.forget_fact(self.cfg, f["id"])  # preview only
        self.assertTrue(prev["preview"]); self.assertEqual(len(b.todos_load()), 2)
        r = b.forget_fact(self.cfg, f["id"], confirm=True)
        self.assertEqual(r["status"], "removed"); self.assertEqual(r["briefings_flagged"], [tr["briefings"][0]["id"]])
        self.assertEqual([t["text"] for t in b.todos_load()], ["Unrelated chore"])
        self.assertNotIn("NDA", (b.MEM / "open-loops.md").read_text())
        self.assertTrue(b.facts_db()["briefings"][0]["relied_on_bad_fact"])
        ctx = b.build_context(self.cfg, [], None, None, "", b.facts_for_use(self.cfg)[1:])
        self.assertNotIn("NDA", ctx)


class TestFactsVsProcesses(MemBase):
    def test_personal_memory_does_not_bleed_into_automations(self):
        (b.MEM / "people.md").write_text("# People\n\n- Sam: designer\n- Priya (manager)\n")
        day = TODAY.isoformat()
        for i in range(3):
            b.add_daily([{"type": "card", "ts": time.time() + i, "start_ts": time.time() + i, "end_ts": time.time() + i + 60, "day": day,
                          "title": "Weekly report for Sam", "summary": "emailed sam@acme.com the numbers with Priya cc'd", "category": "Work"}])
        db = {"items": {"x1": {"id": "x1", "kind": "sequence", "label": "Mail → Sheets (report for Sam)", "steps": ["Mail", "Sheets"],
                               "sources": [f"{day}#1", f"{day}#2"], "status": "new", "history": []}}}
        b.jsave(b.AUTO_DB, db)
        b.automation_draft(self.cfg, "x1")
        sent = OLL.calls[-1][1]
        for leak in ("Sam", "Priya", "sam@acme.com"):
            self.assertNotIn(leak, sent)
        self.assertIn("<person>", sent)

    def test_processes_are_not_stored_as_memories(self):
        c = self.log(TODAY.isoformat(), "Morning")
        keep = b.ingest_facts(self.cfg, "patterns", [f"Every morning opens Mail then Slack then Jira [{c}]",
                                                     f"Focuses best before 11am [{c}]"])
        self.assertEqual([b.strip_cites(k) for k in keep], ["Focuses best before 11am"])
        db = b.facts_db()
        self.assertEqual([b.strip_cites(f["text"]) for f in db["facts"]], ["Focuses best before 11am"])
        self.assertEqual(db["routed"][0]["to"], "automations")


class TestRedactionAndHandoff(MemBase):
    def test_redaction(self):
        raw = ("Deploy key sk-proj-abcdefghijklmnop1234 and ghp_ABCDEFGHIJKLMNOPQRSTuvwx; AWS AKIAABCDEFGHIJKLMNOP. "
               "password: hunter2! Email dana@example.com or call (415) 555-0134. Card 4111 1111 1111 1111, SSN 123-45-6789. "
               "Hash 0123456789abcdef0123456789abcdef01234567. Cite [2026-10-12#3] and memory/projects/pricing.md stay.")
        out = b.redact(raw)
        for secret in ("sk-proj-abcdefghijklmnop1234", "ghp_ABCD", "AKIAABCDEFGHIJKLMNOP", "hunter2", "dana@example.com",
                       "555-0134", "4111 1111", "123-45-6789", "0123456789abcdef0123"):
            self.assertNotIn(secret, out)
        for keep in ("[2026-10-12#3]", "memory/projects/pricing.md", "password: [redacted]", "[email]", "[phone]"):
            self.assertIn(keep, out)

    def test_briefing_is_redacted_and_references_paths(self):
        os.environ["BRIEFING_TEST_ANSWER"] = ""
        (b.MEM / "projects" / "pricing-page.md").write_text("# Pricing page\n")
        orig = b.ollama_chat
        b.ollama_chat = lambda cfg, s_, u, images=None, model=None: ("WHERE YOU LEFT OFF: emailed bob@corp.io the token sk-live-0123456789abcdefXYZ.", None)
        try:
            out = b.cmd_brief(self.cfg, force=True, interactive=False)
        finally:
            b.ollama_chat = orig
        self.assertNotIn("bob@corp.io", out); self.assertNotIn("sk-live", out)
        self.assertIn("Refs: memory/projects/pricing-page.md", out)
        self.assertIn("Handoff style", b.BRIEF_SYS)
        self.assertNotIn("bob@corp.io", b.load_state()["last_brief_text"])


class TestImproveNeverWritesMemory(MemBase):
    def test_run_aborts_if_memory_changes_and_retro_is_proposal_only(self):
        self.cfg["improve_min_free_gb"] = 0
        orig = improve._run
        def sneaky(cfg):
            (b.MEM / "goals.md").write_text("# Goals\n- injected\n")
            return {"proposals": [], "notes": []}
        improve._run = sneaky
        try:
            self.assertIn("aborted", improve.run(self.cfg, force=True))
        finally:
            improve._run = orig
        self.assertEqual(improve.runs_load()[-1]["result"], "aborted")
        mem_before = improve.mem_hash()
        rep = improve.run(dict(self.cfg, improve_repo=str(self.tmp)), force=True)  # no git repo, no data: retro only
        self.assertEqual(improve.mem_hash(), mem_before)
        retro = [p for p in improve.props_load() if p["kind"] == "retro"]
        self.assertTrue(retro and rep["retro"]); self.assertTrue(list((b.HOME / "improve").glob("retro-*.md")))
        self.assertTrue(all(p["status"] == "pending" and not p["diff"] for p in retro))
        self.assertEqual(improve.decide(self.cfg, retro[0]["id"], "approve")["status"], "accepted")
        self.assertEqual(len(b.jload(b.HOME / "improve" / "backlog.json", [])), 1)
        self.assertIn("error", improve.decide(self.cfg, retro[0]["id"], "undo"))
        src = (HERE.parent / "improve.py").read_text()
        for writer in ("ingest_facts(", "merge_file(", "add_daily(", "todo_add(", "curate(", "safe_write("):
            self.assertNotIn(writer, src.replace('"' + writer[:-1], ""))  # the loop has no memory-writing calls


if __name__ == "__main__":
    unittest.main()
