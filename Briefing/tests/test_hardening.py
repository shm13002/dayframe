"""Security/privacy hardening, doctor health check, smallest-diff rule."""
import json, os, socketserver, http.server, stat, sys, tempfile, threading, unittest, urllib.request, urllib.error
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent)); sys.path.insert(0, str(HERE))
os.environ.setdefault("BRIEFING_HOME", tempfile.mkdtemp())
os.environ["BRIEFING_IGNORE_OVERRIDES"] = "1"
import briefing as b  # noqa: E402
import improve  # noqa: E402
import mocks  # noqa: E402

OLL = mocks.FakeOllama()

class HBase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        b.set_home(self.tmp / "home"); b.HOME.mkdir(parents=True)
        b.CONFIG_PATH.write_text(json.dumps({"model": "m", "ollama_url": OLL.url, "request_timeout_s": 5, "dashboard_port": 0,
                                             "dayflow_db": str(self.tmp / "none.sqlite"), "embeddings": False}))
        self.cfg = b.load_config(); b.mem_init()

class TestSecurity(HBase):
    def serve(self, dist_dir=None):
        srv = mocks.start_http_server(b.make_handler({"cfg": self.cfg}, dist_dir))
        port = srv.server_address[1]
        b.CONFIG_PATH.write_text(json.dumps(dict(json.loads(b.CONFIG_PATH.read_text()), dashboard_port=port)))
        srv.RequestHandlerClass = b.make_handler({"cfg": b.load_config()}, dist_dir)
        self.addCleanup(lambda: (srv.shutdown(), srv.server_close()))
        return port

    def req(self, port, path, body=None, headers=None):
        h = {"Content-Type": "application/json"} if body is not None else {}
        h.update(headers or {})
        r = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=json.dumps(body).encode() if body is not None else None, headers=h)
        try:
            with urllib.request.urlopen(r, timeout=10) as resp:
                return resp.status
        except urllib.error.HTTPError as e:
            return e.code

    def test_mutating_endpoints_reject_cross_origin_and_rebinding(self):
        port = self.serve()
        posts = ["/api/todo", "/api/settings", "/api/forget", "/api/memory/forget", "/api/memory/correct", "/api/improve/decide",
                 "/api/automations/run", "/api/resume", "/api/things/sync", "/api/companion/feedback", "/api/brief/feedback"]
        for p in posts:
            for hdr in ({"Origin": "http://evil.com"}, {"Host": "attacker.example:%d" % port}, {"Origin": "null"},
                        {"Sec-Fetch-Site": "cross-site"}, {"Content-Type": "text/plain"}):
                self.assertEqual(self.req(port, p, {"id": "x"}, hdr), 403, (p, hdr))
        self.assertEqual(self.req(port, "/api/doctor", headers={"Host": "evil.com"}), 403)
        self.assertEqual(self.req(port, "/api/doctor"), 200)
        self.assertEqual(self.req(port, "/api/day/..%2F..%2Fetc"), 400)
        self.assertEqual(self.req(port, "/../../etc/passwd"), 400)

    def fetch(self, port, path, headers=None):
        r = urllib.request.Request(f"http://127.0.0.1:{port}{path}", headers=headers or {})
        try:
            with urllib.request.urlopen(r, timeout=10) as resp:
                return resp.status, resp.headers.get("Content-Type"), resp.read()
        except urllib.error.HTTPError as e:
            return e.code, e.headers.get("Content-Type"), b""

    def test_react_app_is_served_from_dist_only(self):
        dist = self.tmp / "dist"
        (dist / "assets").mkdir(parents=True)
        (dist / "index.html").write_text("<!doctype html><div id=root></div>")
        (dist / "assets" / "app.js").write_text("console.log(1)")
        (dist / "assets" / "app.css").write_text("body{}")
        (dist / "assets" / "font.ttf").write_bytes(b"\x00\x01")
        (dist / "notes.txt").write_text("not a web type")
        (self.tmp / "secret.txt").write_text("outside dist")
        port = self.serve(dist)

        status, ctype, body = self.fetch(port, "/app/")
        self.assertEqual((status, ctype), (200, "text/html; charset=utf-8"))
        self.assertIn(b"id=root", body)
        self.assertEqual(self.fetch(port, "/app/assets/app.js")[:2], (200, "text/javascript; charset=utf-8"))
        self.assertEqual(self.fetch(port, "/app/assets/app.css")[:2], (200, "text/css; charset=utf-8"))
        self.assertEqual(self.fetch(port, "/app/assets/font.ttf")[:2], (200, "font/ttf"))  # no charset on binary types
        self.assertEqual(self.fetch(port, "/app/memory")[0], 200)  # app routes fall back to the shell
        self.assertEqual(self.fetch(port, "/app/assets/missing.js")[0], 404)
        self.assertEqual(self.fetch(port, "/app/notes.txt")[0], 404)  # only known web types
        # encoded traversal must never leave dist/
        for evil in ("/app/%2e%2e/secret.txt", "/app/%2E%2E%2Fsecret.txt", "/app/assets/%2e%2e/%2e%2e/secret.txt",
                     "/app/..%2fsecret.txt", "/app/%00index.html", "/app/%5c..%5csecret.txt"):
            self.assertIn(self.fetch(port, evil)[0], (400, 404), evil)
        # the same origin checks as the API
        self.assertEqual(self.fetch(port, "/app/", {"Host": "evil.com"})[0], 403)
        self.assertEqual(self.fetch(port, "/app/", {"Sec-Fetch-Site": "cross-site"})[0], 403)

    def test_react_app_missing_build_is_404(self):
        port = self.serve(self.tmp / "no-dist")
        self.assertEqual(self.fetch(port, "/app/")[0], 404)

    def test_dashboard_binds_loopback_only(self):
        src = Path(b.__file__).read_text()
        self.assertIn('S(("127.0.0.1", cfg["dashboard_port"])', src)
        self.assertNotIn("0.0.0.0", src)

    def test_owner_only_permissions(self):
        p = b.MEM / "goals.md"; os.chmod(p, 0o644); os.chmod(b.MEM, 0o755)
        (b.HOME / "automations").mkdir(exist_ok=True)
        sc = b.HOME / "automations" / "x.sh"; sc.write_text("#!/bin/sh\n"); os.chmod(sc, 0o755)
        b.harden_perms()
        mode = lambda q: stat.S_IMODE(q.stat().st_mode)
        self.assertEqual(mode(p), 0o600); self.assertEqual(mode(b.MEM), 0o700); self.assertEqual(mode(b.HOME), 0o700)
        self.assertEqual(mode(sc), 0o700)  # scripts stay runnable by you only
        b.jsave(b.DATA / "new.json", {})  # umask applies to new files
        self.assertEqual(mode(b.DATA / "new.json") & 0o077, 0)
        self.assertTrue(next(c for c in b.doctor(self.cfg)["checks"] if c["job"] == "permissions")["state"] == "ok")

    def test_no_shell_injection(self):
        evil = 'x" & do shell script "rm -rf ~" & "'
        esc = b.osa_escape(evil)
        self.assertNotIn('" &', esc.replace('\\"', ""))  # every quote is escaped
        b.DESKTOP_CALLS.clear()  # run_on_mac records these instead of running them in tests
        orig_mac = b.is_mac
        b.is_mac = lambda: True
        try:
            b.speak("-o /tmp/pwn.aiff hello", dict(self.cfg, speak=True))
            b.notify(evil, evil)
        finally:
            b.is_mac = orig_mac
        calls = b.DESKTOP_CALLS
        self.assertEqual(len(calls), 3)  # say, the notch hand-off, and the notification it fell back to
        notice = next(c for c in calls if c[0] == "open")
        self.assertRegex(notice[-1], r"^dayframe://notice\?id=[0-9a-f-]+$")  # the text goes in a file, never the URL
        for c in calls:
            self.assertIsInstance(c, list)  # argv lists, never a shell string
        say = next(c for c in calls if c[0] == "say")
        self.assertEqual(say[-2], "--")  # text can't be read as an option
        url = b.things_add_url(self.cfg, {"id": "ab12", "text": 'Buy milk" ; open -a Calculator & "', "source": "x"})
        self.assertNotIn(" ", url); self.assertNotIn('"', url); self.assertTrue(url.startswith("things:///add?"))

    def test_path_traversal_guarded(self):
        with self.assertRaises(ValueError):
            b.safe_mem_path(b.MEM / ".." / ".." / "etc" / "passwd")
        p = b._fact_file({"kind": "project:../../../etc/passwd"})
        self.assertIn(b.MEM.resolve(), p.resolve().parents)
        bad = "--- a/../outside.py\n+++ b/../outside.py\n@@ -1,1 +1,1 @@\n-a\n+b\n"
        self.assertFalse(improve.check_patch(self.cfg, bad, self.tmp)[0])


class TestDoctor(HBase):
    def test_reports_each_job_with_time_and_error(self):
        d = b.doctor(self.cfg)
        jobs = {c["job"]: c for c in d["checks"]}
        for j in ("recorder", "distill", "companion", "improve", "cleanup", "ollama", "permissions", "git"):
            self.assertIn(j, jobs)
        self.assertEqual(jobs["recorder"]["state"], "error"); self.assertIn("not found", jobs["recorder"]["error"].lower() + "not found")
        self.assertEqual(jobs["distill"]["state"], "never")
        b.job_status("distill", False, error="Ollama not reachable")
        b.job_status("improve", True, detail="no change needed")
        b.job_status("companion", True)
        jobs = {c["job"]: c for c in b.doctor(self.cfg)["checks"]}
        self.assertEqual((jobs["distill"]["state"], jobs["distill"]["error"]), ("error", "Ollama not reachable"))
        self.assertEqual(jobs["improve"]["state"], "ok"); self.assertTrue(jobs["improve"]["last_run"])
        st = b.jload(b.HOME / "status.json", {}); st["companion"]["last_run"] -= 7200; b.jsave(b.HOME / "status.json", st)
        self.assertEqual({c["job"]: c for c in b.doctor(self.cfg)["checks"]}["companion"]["state"], "late")
        self.assertEqual(jobs["ollama"]["state"], "error")  # model "m" not pulled on the fake server
        txt = b.doctor_text(self.cfg)
        self.assertIn("distill", txt); self.assertIn("↳ Ollama not reachable", txt)

    def test_cli_records_job_results(self):
        b.main(["cleanup"])
        self.assertIn("cleanup", b.jload(b.HOME / "status.json", {}))
        orig = b.cmd_distill
        b.cmd_distill = lambda cfg: (_ for _ in ()).throw(RuntimeError("db locked"))
        try:
            with self.assertRaises(RuntimeError):
                b.main(["distill"])
        finally:
            b.cmd_distill = orig
        j = b.jload(b.HOME / "status.json", {})["distill"]
        self.assertFalse(j["ok"]); self.assertIn("db locked", j["error"])


class TestJobOutcome(HBase):
    def test_failure_from_real_errors_not_keywords(self):
        b.CONFIG_PATH.write_text(json.dumps(dict(json.loads(b.CONFIG_PATH.read_text()), ollama_url="http://127.0.0.1:9")))
        b.inbox_add("note", "call the dentist about the error in my bill")  # 'error' in content must not matter
        with self.assertRaises(SystemExit) as e:
            b.main(["distill"])
        self.assertEqual(e.exception.code, 1)
        j = b.jload(b.HOME / "status.json", {})["distill"]
        self.assertFalse(j["ok"]); self.assertIn("Ollama not reachable", j["error"])
        b.CONFIG_PATH.write_text(json.dumps(dict(json.loads(b.CONFIG_PATH.read_text()), ollama_url=OLL.url)))
        b.main(["cleanup"])  # no Dayflow recordings yet is not a failure
        self.assertTrue(b.jload(b.HOME / "status.json", {})["cleanup"]["ok"])

    def test_orb_checkins_rate_limited(self):
        b.job_status("companion", True, throttle=60)
        t = b.jload(b.HOME / "status.json", {})["companion"]["last_run"]
        (b.HOME / "status.json").write_text(json.dumps({"companion": {"last_run": t, "ok": True, "marker": 1}}))
        b.job_status("companion", True, throttle=60)
        self.assertEqual(b.jload(b.HOME / "status.json", {})["companion"].get("marker"), 1)  # not rewritten

    def test_port_in_use_is_explained(self):
        import errno, socket
        s = socket.socket()
        try:
            s.bind(("127.0.0.1", 0)); s.listen(1); self.addCleanup(s.close)
            cfg = dict(self.cfg, dashboard_port=s.getsockname()[1])
        except PermissionError:
            s.close()
            cfg = dict(self.cfg, dashboard_port=8765)
            orig_init = http.server.HTTPServer.__init__
            def _busy_init(*a, **kw):
                raise OSError(errno.EADDRINUSE, "Address already in use")
            http.server.HTTPServer.__init__ = _busy_init
            self.addCleanup(lambda: setattr(http.server.HTTPServer, "__init__", orig_init))
        b.time.sleep, orig = (lambda *_: None), b.time.sleep
        try:
            msg = b.cmd_serve(cfg)
        finally:
            b.time.sleep = orig
        self.assertIn("in use", msg)
        self.assertIn("in use", b.jload(b.HOME / "status.json", {})["dashboard"]["error"])


class TestSmallestDiff(HBase):
    def setUp(self):
        super().setUp()
        self.repo = HERE.parent

    def test_growth_and_safety_net_cuts_rejected_deletions_ranked_first(self):
        src = (self.repo / "briefing.py").read_text().splitlines()
        i = next(n for n, l in enumerate(src, 1) if l.startswith("def stuck_score("))
        grow = f"--- a/briefing.py\n+++ b/briefing.py\n@@ -{i + 1},1 +{i + 1},40 @@\n {src[i]}\n" + "".join(f"+    x{k} = {k}\n" for k in range(39))
        test = "--- /dev/null\n+++ b/tests/improve_cases/test_a.py\n@@ -0,0 +1,1 @@\n+import unittest\n"
        b.ollama_chat, orig = (lambda *a, **k: (test + grow, None)), b.ollama_chat
        try:
            improve.comp_cases, oc = (lambda: []), improve.comp_cases
            self.assertIsNone(improve.code_candidate(dict(self.cfg, improve_code_model="c"), {"id": "companion_interrupts", "text": "x"})[0])
        finally:
            b.ollama_chat, improve.comp_cases = orig, oc
        self.assertEqual(improve.diff_size(test + grow), (39, 0))
        j = next(n for n, l in enumerate(src, 1) if "raise" in l and n > i)
        cut = f"--- a/briefing.py\n+++ b/briefing.py\n@@ -{j},1 +{j},0 @@\n-{src[j - 1]}\n"
        ok, why = improve.check_patch(self.cfg, cut, self.repo)
        self.assertFalse(ok); self.assertIn("safety net", why)
        small = {"kind": "code", "patch": "--- a/x\n+++ b/x\n@@ -1,3 +1,1 @@\n-a\n-b\n+c\n"}
        big = {"kind": "code", "patch": "--- a/x\n+++ b/x\n@@ -1,1 +1,3 @@\n-a\n+b\n+c\n+d\n"}
        param = {"kind": "param", "change": {"companion_threshold_base": 0.8}}
        self.assertEqual(sorted([big, small, param], key=improve.rank_key), [param, small, big])


if __name__ == "__main__":
    unittest.main()
