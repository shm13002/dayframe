"""claude_cli / codex_cli / grok_cli backends: the user's own Claude / ChatGPT / Grok plan via the official CLIs."""
import json, os, stat, sys, tempfile, unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import briefing as b
import mocks

OLL = mocks.FakeOllama()

FAKE_CLAUDE = """#!/bin/bash
read -r -d '' INPUT
if [[ "$FAKE_MODE" == "auth" ]]; then
  echo '{"is_error":true,"result":"Failed to authenticate: OAuth session expired"}'; exit 1
fi
echo '{"is_error":false,"result":"claude says hi","usage":{"input_tokens":12,"output_tokens":3}}'
"""
FAKE_CODEX = """#!/bin/bash
cat >/dev/null
echo '{"type":"thread.started"}'
echo '{"type":"item.completed","item":{"type":"agent_message","text":"codex says hi"}}'
echo '{"type":"turn.completed","usage":{"input_tokens":20,"output_tokens":4}}'
"""
# Grok CLI 0.2.99: prompt from --prompt-file, one JSON object out. The error line is the
# real one it prints when its 7-day sign-in has expired.
FAKE_GROK = """#!/bin/bash
printf '%s\\n' "$@" > "$(dirname "$0")/grok-args.log"
while [[ $# -gt 0 ]]; do [[ "$1" == "--prompt-file" ]] && cp "$2" "$(dirname "$0")/grok-prompt.txt"; shift; done
if [[ "$FAKE_MODE" == "auth" ]]; then
  echo '{"type":"error","message":"Not signed in. To authenticate without a browser, run:\\n  grok login --device-code"}'; exit 1
fi
echo '{"text":"grok says hi","stopReason":"EndTurn","sessionId":"s1","usage":{"input_tokens":7,"cache_read_input_tokens":40,"output_tokens":5,"reasoning_tokens":2}}'
"""


class TestCLIBackends(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.bin = Path(self.tmp.name)
        for name, body in (("claude", FAKE_CLAUDE), ("codex", FAKE_CODEX), ("grok", FAKE_GROK)):
            p = self.bin / name
            p.write_text(body)
            p.chmod(p.stat().st_mode | stat.S_IEXEC)
        self._dirs, self._home = b.CLI_DIRS, b.HOME
        b.CLI_DIRS = [str(self.bin)]
        b.HOME = Path(self.tmp.name) / "home"
        b.HOME.mkdir()
        os.environ.pop("FAKE_MODE", None)

    def tearDown(self):
        b.CLI_DIRS, b.HOME = self._dirs, self._home
        os.environ.pop("FAKE_MODE", None)
        self.tmp.cleanup()

    def cfg(self, backend):
        return dict(b.DEFAULTS, model="m", ollama_url=OLL.url, request_timeout_s=5, llm_backend=backend)

    def test_claude_text_and_usage(self):
        out, err = b.cli_chat(self.cfg("claude_cli"), "sys", "hello")
        self.assertIsNone(err)
        self.assertEqual(out, "claude says hi")
        rows = [json.loads(l) for l in (b.HOME / "telemetry.jsonl").read_text().splitlines()]
        self.assertEqual((rows[-1]["backend"], rows[-1]["tokens_in"], rows[-1]["tokens_out"]), ("claude_cli", 12, 3))

    def test_codex_jsonl(self):
        out, err = b.cli_chat(self.cfg("codex_cli"), "sys", "hello")
        self.assertIsNone(err)
        self.assertEqual(out, "codex says hi")

    def test_auth_error_is_readable_and_falls_back_to_ollama(self):
        os.environ["FAKE_MODE"] = "auth"
        out, err = b.cli_chat(self.cfg("claude_cli"), "sys", "hello")
        self.assertIn("/login", err)
        out, err = b.ollama_chat(self.cfg("claude_cli"), "You are a helpful assistant.", "hi")
        self.assertIsNone(err)  # answered by the local fallback

    def test_missing_cli(self):
        b.CLI_DIRS = [str(self.bin / "nope")]
        os.environ["PATH"], old = "/nonexistent", os.environ.get("PATH", "")
        try:
            self.assertIn("not found", b.cli_chat(self.cfg("codex_cli"), "s", "u")[1])
        finally:
            os.environ["PATH"] = old

    def test_grok_text_and_usage(self):
        out, err = b.cli_chat(self.cfg("grok_cli"), "sys", "hello")
        self.assertIsNone(err)
        self.assertEqual(out, "grok says hi")
        rows = [json.loads(l) for l in (b.HOME / "telemetry.jsonl").read_text().splitlines()]
        self.assertEqual((rows[-1]["backend"], rows[-1]["tokens_in"], rows[-1]["tokens_out"]), ("grok_cli", 47, 5))
        self.assertTrue(b.is_cli(self.cfg("grok_cli")))
        self.assertEqual(b.llm_name(self.cfg("grok_cli")), "Grok (your plan)")

    def test_grok_prompt_goes_through_a_file_that_is_removed(self):
        b.cli_chat(self.cfg("grok_cli"), "be brief", "my private note")
        args = (self.bin / "grok-args.log").read_text().splitlines()
        self.assertNotIn("my private note", "\n".join(args))  # never on the command line
        self.assertEqual((self.bin / "grok-prompt.txt").read_text(), "my private note")
        self.assertEqual(args[args.index("--system-prompt-override") + 1], "be brief")
        self.assertEqual(list((b.HOME / ".cli-sandbox").glob("*")), [])  # prompt file cleaned up

    def test_grok_writes_text_only(self):
        b.cli_chat(self.cfg("grok_cli"), "sys", "hello")
        args = (self.bin / "grok-args.log").read_text().splitlines()
        for flag in ("--disable-web-search", "--no-subagents", "--no-memory", "--no-plan"):
            self.assertIn(flag, args)
        self.assertEqual(args[args.index("--max-turns") + 1], "1")
        self.assertIn("run_terminal_cmd", args[args.index("--disallowed-tools") + 1])

    def test_grok_not_signed_in(self):
        os.environ["FAKE_MODE"] = "auth"
        out, err = b.cli_chat(self.cfg("grok_cli"), "sys", "hello")
        self.assertIn("Not signed in", err)
        self.assertIn("grok login", err)
        out, err = b.ollama_chat(self.cfg("grok_cli"), "You are a helpful assistant.", "hi")
        self.assertIsNone(err)  # answered by the local fallback

    def test_images_stay_local(self):
        out, err = b.ollama_chat(self.cfg("claude_cli"), "sys", "what is on screen", images=["aGk="])
        self.assertNotEqual(out, "claude says hi")


if __name__ == "__main__":
    unittest.main()
