"""Briefings, check-ins and nudges go to Dayframe's notch pill; the old dialogs are only the fallback."""
import json, os, sys, tempfile, unittest
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent)); sys.path.insert(0, str(HERE))
os.environ.setdefault("BRIEFING_HOME", tempfile.mkdtemp())
os.environ["BRIEFING_IGNORE_OVERRIDES"] = "1"
import briefing as b  # noqa: E402
import mocks  # noqa: E402,F401  (keeps the tests off the real Mac)


class TestNotch(unittest.TestCase):
    def setUp(self):
        b.set_home(Path(tempfile.mkdtemp()) / "home"); b.HOME.mkdir(parents=True)
        self.orig_mac, b.is_mac = b.is_mac, lambda: True
        b.DESKTOP_CALLS.clear()
        os.environ.pop("BRIEFING_TEST_ANSWER", None)
        self.seen = []

    def tearDown(self):
        b.is_mac, b.NOTCH_RESPONDER = self.orig_mac, None

    def dayframe(self, answer=None):
        """Play Dayframe's part: read the notice, acknowledge it, maybe answer."""
        def respond(nid):
            self.seen.append(json.loads((b.NOTICES / f"{nid}.json").read_text()))
            (b.NOTICES / f"{nid}.ack").write_text("")
            if answer is not None:
                (b.NOTICES / f"{nid}.answer").write_text(json.dumps(answer))
        b.NOTCH_RESPONDER = respond

    def calls(self):
        return [" ".join(c) for c in b.DESKTOP_CALLS]

    def test_briefing_goes_to_the_notch_not_a_dialog(self):
        self.dayframe()
        b.show("WHERE YOU LEFT OFF: editing x.\nNEXT STEPS:\n1. Ship it")
        self.assertEqual(self.seen[0]["kind"], "brief")
        self.assertIn("Ship it", self.seen[0]["text"])
        self.assertTrue(any(c.startswith("open -g dayframe://notice?id=") for c in self.calls()), self.calls())
        self.assertFalse(any(c.startswith("osascript") for c in self.calls()), self.calls())
        self.assertEqual([p.suffix for p in b.NOTICES.iterdir()], [".json"])   # ack cleaned up

    def test_without_dayframe_the_dialog_still_appears(self):
        b.show("WHERE YOU LEFT OFF: editing x.")
        self.assertTrue(any(c.startswith("osascript") and "Where you left off" in c for c in self.calls()), self.calls())
        self.assertEqual(list(b.NOTICES.iterdir()), [])   # never shown late

    def test_check_in_answer_comes_back_from_the_notch(self):
        self.dayframe({"text": "  writing the notch card  "})
        self.assertEqual(b.ask("What are you working on?", title="Check-in"), "writing the notch card")
        self.assertEqual((self.seen[0]["kind"], self.seen[0]["title"], self.seen[0]["wait"]), ("ask", "Check-in", 600))
        self.dayframe({"skip": True})
        self.assertEqual(b.ask("Goal?"), "")

    def test_nudge_is_a_peek(self):
        self.dayframe()
        b.notify("You've been on YouTube 25 min", "Gentle nudge")
        self.assertEqual((self.seen[0]["kind"], self.seen[0]["title"]), ("peek", "Gentle nudge"))
        self.assertFalse(any("display notification" in c for c in self.calls()))

    def test_fallback_briefing_is_sharp(self):
        todos = [{"text": "Old thing", "created": "2026-09-01", "done": False},
                 {"text": "Done thing", "created": "2026-10-13", "done": True},
                 {"text": "Fix the Ollama timeout", "created": "2026-10-12", "done": False},
                 {"text": "Draft the API proposal", "created": "2026-10-13", "done": False}]
        import datetime as dt
        text = b.fallback_brief(todos, today=dt.date(2026, 10, 13))
        self.assertNotIn("error", text.lower())
        self.assertIn("NEXT STEPS:\n1. Draft the API proposal\n2. Fix the Ollama timeout", text)
        self.assertNotIn("Old thing", text.split("\n\n")[0])
        self.assertIn("1 more open loop", text)


    def test_resume_offer_goes_to_the_notch_and_opens_targets(self):
        b.DATA.mkdir(parents=True, exist_ok=True)
        b.proj_save("dayframe", {"sessions": [{"day": "2026-10-13", "start": 100, "minutes": 45, "title": "Notch card", "src": "#1"}],
                                 "apps": {"Xcode": 3, "Terminal": 2}, "urls": {"https://github.com/me/dayframe/pull/1": 2}, "files": {}})
        self.dayframe({"resume": True})
        out = b.offer_resume(b.load_config())
        self.assertEqual(self.seen[0]["kind"], "resume")
        self.assertEqual(self.seen[0]["title"], "Resume dayframe?")
        self.assertIn("Apps: Xcode, Terminal", self.seen[0]["text"])
        self.assertIn("resumed:", out)
        self.assertTrue(any('tell application "Xcode" to activate' in c for c in self.calls()), self.calls())
        self.assertFalse(any("display dialog" in c for c in self.calls()), self.calls())

    def test_resume_offer_declined_from_the_notch_opens_nothing(self):
        b.DATA.mkdir(parents=True, exist_ok=True)
        b.proj_save("dayframe", {"sessions": [], "apps": {"Xcode": 2}, "urls": {}, "files": {}})
        self.dayframe({"skip": True})
        out = b.offer_resume(b.load_config())
        self.assertEqual(out, "declined")
        self.assertFalse(any("activate" in c or "display dialog" in c for c in self.calls()), self.calls())

    def test_resume_falls_back_to_dialog_without_dayframe(self):
        b.DATA.mkdir(parents=True, exist_ok=True)
        b.proj_save("dayframe", {"sessions": [], "apps": {"Xcode": 2}, "urls": {}, "files": {}})
        out = b.offer_resume(b.load_config())
        self.assertEqual(out, "declined")
        self.assertTrue(any("display dialog" in c and "Resume dayframe?" in c for c in self.calls()), self.calls())


if __name__ == "__main__":
    unittest.main()
