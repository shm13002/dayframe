"""Test fixtures: in-process fake Ollama + realistic Dayflow / Meetily databases.

Importing this module also keeps every test off the real Mac (every test file imports it)."""
import hashlib, http.server, json, random, re, sqlite3, subprocess, threading, datetime as dt, os

# Tests must never act on the user's Mac: no dialogs, notifications, speech, microphone, Messages,
# Things to-dos, opened apps or links. briefing.run_on_mac() records such commands instead of running
# them while BRIEFING_NO_DESKTOP is set. The tripwire below fails any test that reaches the Mac
# another way, instead of popping a dialog or a Chrome tab on the user's screen.
os.environ["BRIEFING_NO_DESKTOP"] = "1"
DESKTOP_TOOLS = {"osascript", "open", "say", "afplay", "ffmpeg", "screencapture", "shortcuts"}


class _GuardedPopen(subprocess.Popen):
    def __init__(self, args, *a, **kw):
        argv = args if isinstance(args, (list, tuple)) else str(args).split()
        if argv and os.path.basename(str(argv[0])) in DESKTOP_TOOLS:
            raise AssertionError(f"a test tried to act on the real Mac: {list(argv)[:3]} (go through briefing.run_on_mac)")
        super().__init__(args, *a, **kw)


subprocess.Popen = _GuardedPopen  # subprocess.run creates its process through Popen too

class FakeOllama:
    """mode: ok | garbage | fenced | empty | down(=server stopped)"""
    def __init__(self):
        self.mode, self.calls, self.embeds = "ok", [], 0
        self.openai_models = []   # ids served at /v1/models (OpenAI-compatible mode, e.g. LM Studio)
        me = self
        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a): pass
            def do_GET(self):
                self.send_response(200); self.end_headers()
                self.wfile.write(json.dumps({"data": [{"id": i} for i in me.openai_models]}).encode() if self.path.endswith("/models") else b'{"models":[]}')
            def do_POST(self):
                b = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                if self.path.startswith("/v1/"):
                    return me.openai(self, self.path[3:], b)
                out = me.reply(self.path, b)
                self.send_response(200); self.end_headers()
                if isinstance(out, dict) and "__stream__" in out:
                    if me.mode == "garbage":
                        self.wfile.write(b"not json\n"); return
                    for piece in out["__stream__"]:
                        self.wfile.write((json.dumps({"message": {"content": piece}, "done": False}) + "\n").encode()); self.wfile.flush()
                    self.wfile.write(b'{"message":{"content":""},"done":true}\n'); return
                self.wfile.write(json.dumps(out).encode())
        self.srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.url = f"http://127.0.0.1:{self.srv.server_address[1]}"
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()

    def openai(self, h, path, b):
        """OpenAI-compatible endpoints (LM Studio): translate to the Ollama-shaped reply() and back."""
        if path == "/embeddings":
            out = self.reply("/api/embed", b)
            body = {"data": [{"index": i, "embedding": v} for i, v in enumerate(out.get("embeddings") or [])]} if "embeddings" in out else {"error": out.get("error")}
            h.send_response(200); h.end_headers(); h.wfile.write(json.dumps(body).encode()); return
        msgs = [dict(m) for m in b["messages"]]
        u = msgs[1]["content"]
        if isinstance(u, list):  # text + image_url parts
            msgs[1]["content"] = "".join(p.get("text", "") for p in u if p.get("type") == "text")
            msgs[1]["images"] = [p["image_url"]["url"].split(",", 1)[1] for p in u if p.get("type") == "image_url"]
        out = self.reply("/api/chat", dict(b, messages=msgs))
        h.send_response(200); h.end_headers()
        if isinstance(out, dict) and "__stream__" in out:
            if self.mode == "garbage":
                h.wfile.write(b"data: not json\n\n"); return
            for piece in out["__stream__"]:
                h.wfile.write(("data: " + json.dumps({"choices": [{"delta": {"content": piece}}]}) + "\n\n").encode()); h.wfile.flush()
            h.wfile.write(b"data: [DONE]\n\n"); return
        h.wfile.write(json.dumps({"choices": [{"message": {"role": "assistant", "content": out["message"]["content"]}}]}).encode())

    @staticmethod
    def vec(t):
        v = [0.0] * 64
        for w in re.findall(r"\w+", t.lower()):
            v[int(hashlib.md5(w.encode()).hexdigest(), 16) % 64] += 1
        return v

    def reply(self, path, b):
        if path == "/api/embed":
            self.embeds += 1
            if self.mode == "garbage":
                return {"error": "no embed model"}
            return {"embeddings": [self.vec(t) for t in b["input"]]}
        s, u = b["messages"][0]["content"], b["messages"][1]["content"]
        self.calls.append((s[:30], u))
        self.last_images = b["messages"][1].get("images")
        self.last_model = b.get("model")
        if b.get("stream"):
            return {"__stream__": self.stream_text(s, u)}
        if self.mode == "garbage":
            return {"message": {"content": "Sure! Here you go: {not json, ]"}}
        if self.mode == "empty":
            return {"message": {"content": ""}}
        c = self.content(s, u)
        if self.mode == "fenced" and c.lstrip().startswith("{"):
            c = "Here is the JSON:\n```json\n" + c + "\n```\nHope that helps!"
        return {"message": {"content": c}}

    def stream_text(self, s, u):
        if "Socratic nudge" in s:
            txt = "What rule lets you split ∫ of a sum into a sum of integrals?"
        elif "full worked solution" in s:
            txt = "Step 1: split the integral. Step 2: integrate each term. Answer: x³/3 + C.\nANCHOR: Step 3"
        elif "next concrete step" in s:
            txt = "Apply the power rule to x²: raise the exponent by one and divide."
        elif "minimal fix" in s:
            txt = "The variable is None because load() returns early.\n```python\nif data is None:\n    return []\n```"
        elif "formula" in s:
            txt = "```\n=XLOOKUP(A2,Sheet2!A:A,Sheet2!B:B)\n```\nLooks up A2 in Sheet2."
        elif "numbered steps" in s:
            txt = "1. Open the Privacy section.\n2. Click Screen Recording.\nANCHOR: Privacy & Security"
        else:
            txt = "Here is a direct answer about the page. ANCHOR: NotOnScreen"
        return [txt[i:i + 7] for i in range(0, len(txt), 7)]

    def content(self, s, u):
        day = (re.findall(r"\[(\d{4}-\d\d-\d\d)#(\d+)\]", u) or [("2026-01-01", "1")])[0]
        src = f"[{day[0]}#{day[1]}]"
        if s.startswith("Extract"):
            return json.dumps({"projects": [{"name": "Landing Page", "facts": [f"Chose blue CTA in hero.css {src}"]},
                                            {"name": "Café ☕ App", "facts": [f"Menu in Swift {src}"]}],
                               "profile": [f"Uses Cursor and Figma {src}"], "goals": [f"Ship landing page by Friday {src}"],
                               "open_loops": [f"Fix mobile nav {src}"], "resolved_loops": [], "people": [f"Sam, designer {src}"],
                               "patterns": ["Deep work 9-11am"]})
        if s.startswith("You maintain one"):
            ex = u.split("EXISTING FILE:\n", 1)[1].split("\n\nNEW FACTS", 1)[0]
            nf = u.split("NEW FACTS", 1)[1].split("\n", 1)[1]
            return ex.rstrip() + "\n" + "\n".join(l for l in nf.splitlines() if l not in ex)
        if s.startswith("You anticipate"):
            mode = re.search(r"Activity mode: (\w+)", s).group(1)
            q = {"study": ("How do I get from step 2 to step 3 of this integral?", "Step 3"),
                 "coding": ("Why is this raising TypeError: 'NoneType' object is not iterable?", "TypeError"),
                 "spreadsheets": ("Why does C4 show #REF!?", "#REF!"), "writing": ("How can I make this intro punchier?", "Introduction"),
                 "admin": ("Where do I allow screen recording?", "Privacy & Security"), "unknown": ("What am I trying to do here?", "")}.get(mode, ("What does this mean?", "Ghost anchor"))
            return json.dumps({"goal": "g", "questions": [{"text": q[0], "kind": "how-to", "anchor": q[1]},
                                                          {"text": "Explain this term", "kind": "explain", "anchor": "zzz not on screen"},
                                                          {"text": "", "kind": "x"}]})
        if s.startswith("You write small"):
            return json.dumps({"kind": "shell", "title": "Open work set", "summary": "Opens the PR.",
                               "script": "open 'https://github.com/me/site/pull/12'", "test_notes": "-"})
        if s.startswith("You are a quiet"):
            return json.dumps({"intent": "Back to the hero", "why": "routine", "confidence": 0.8, "say": "Back?",
                               "actions": [{"type": "open_app", "target": "Cursor", "label": "Cursor"},
                                           {"type": "open_app", "target": "NotAnApp", "label": "x"},
                                           {"type": "add_todo", "target": "Ping Sam", "label": "To-do"}]})
        if s.startswith("Answer"):
            return "You edited hero.css [daily/x.md#1]." if "hero.css" in u else "I don't have that."
        if "weekly" in s.lower():
            return "## Summary\nGood week with lots of landing page work.\n## Wins\n- shipped"
        if s.startswith("Reply in 2"):
            return "Nice work today. Start with the nav tomorrow."
        return "WHERE YOU LEFT OFF: hero.css in Cursor.\nYOUR GOAL: Ship by Friday.\nNEXT STEPS:\n1. a\n2. b\n3. c"

    def stop(self):
        self.srv.shutdown(); self.srv.server_close()

ACTS = [("Landing page hero CSS", "Edited ~/code/site/hero.css in Cursor. I need to fix the mobile nav overlap.", "Work", '{"apps":["Cursor"]}'),
        ("Design review with Sam", "Figma review; chose blue CTA. https://github.com/me/site/pull/12", "Work", '{"apps":["Figma","Zoom"]}'),
        ("YouTube", "Watched videos", "Distraction", '{"apps":["Safari"]}'),
        ("Email triage", "Mail inbox; follow up with Dana about invoice", "Admin", '{"apps":["Mail"]}'),
        ("Banking", "Checked BankCo balance", "Personal", None),
        ("Café ☕ app — 日本語 メニュー", "Built the menu screen in Xcode; RTL test שלום", "Work", '{"apps":["Xcode"]}')]

def make_dayflow(path, weeks=6, per_day=8, seed=7, empty=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    c = sqlite3.connect(path)
    c.executescript("""CREATE TABLE analysis_batches(id INTEGER PRIMARY KEY,status TEXT);
    CREATE TABLE timeline_cards(id INTEGER PRIMARY KEY,batch_id INT,start TEXT,end TEXT,start_ts INT,end_ts INT,day DATE,
      title TEXT,summary TEXT,category TEXT,subcategory TEXT,detailed_summary TEXT,metadata TEXT,is_deleted INT DEFAULT 0);
    CREATE TABLE screenshots(id INTEGER PRIMARY KEY,captured_at INT,file_path TEXT,file_size INT,is_deleted INT DEFAULT 0);
    CREATE TABLE batch_screenshots(batch_id INT,screenshot_id INT);""")
    if empty:
        c.commit(); return 0
    rnd, n = random.Random(seed), 0
    today = dt.date.today()
    for back in range(weeks * 7, 0, -1):
        day = today - dt.timedelta(days=back)
        t = dt.datetime.combine(day, dt.time(9, 0)).timestamp()
        for k in range(per_day):
            a = ACTS[(k + back) % len(ACTS)] if rnd.random() < 0.3 else ACTS[k % len(ACTS)]
            dur = rnd.choice([20, 30, 45, 60]) * 60
            n += 1
            c.execute("INSERT INTO analysis_batches VALUES(?, 'completed')", (n,))
            c.execute("INSERT INTO timeline_cards(batch_id,start,end,start_ts,end_ts,day,title,summary,category,detailed_summary,metadata,is_deleted)"
                      " VALUES(?,?,?,?,?,?,?,?,?,?,?,?)", (n, "", "", int(t), int(t + dur), day.isoformat(), a[0], a[1], a[2],
                                                          a[1] + " (detail)", a[3], 1 if rnd.random() < 0.02 else 0))
            t += dur + rnd.choice([5, 10, 20]) * 60
    c.commit(); c.close()
    return n

def make_meetily(path):
    m = sqlite3.connect(path)
    m.executescript("""CREATE TABLE meetings(id TEXT PRIMARY KEY,title TEXT,created_at TEXT,updated_at TEXT);
    CREATE TABLE transcripts(id TEXT PRIMARY KEY,meeting_id TEXT,transcript TEXT,timestamp TEXT,summary TEXT,action_items TEXT,key_points TEXT);
    CREATE TABLE summary_processes(meeting_id TEXT PRIMARY KEY,status TEXT,created_at TEXT,updated_at TEXT,result TEXT);
    CREATE TABLE meeting_notes(meeting_id TEXT PRIMARY KEY,notes_markdown TEXT,created_at TEXT,updated_at TEXT);""")
    ts = (dt.datetime.now() - dt.timedelta(hours=3)).strftime("%Y-%m-%dT%H:%M:%S")
    m.execute("INSERT INTO meetings VALUES('m1','Launch sync with Sam',?,?)", (ts, ts))
    m.execute("INSERT INTO transcripts VALUES('t1','m1','we launch Friday. I need to finalize pricing.',?,NULL,'- Send pricing sheet to Sam',NULL)", (ts,))
    m.execute("INSERT INTO summary_processes VALUES('m1','completed',?,?,?)", (ts, ts, json.dumps({"markdown": "Friday launch."})))
    m.execute("INSERT INTO meetings VALUES('m2','BankCo review',?,?)", (ts, ts))
    m.commit(); m.close()
