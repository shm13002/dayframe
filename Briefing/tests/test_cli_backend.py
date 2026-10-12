"""claude_cli / codex_cli backends: the user's own Claude / ChatGPT plan via the official CLIs."""
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


class TestCLIBackends(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.bin = Path(self.tmp.name)
        for name, body in (("claude", FAKE_CLAUDE), ("codex", FAKE_CODEX)):
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

    def test_images_stay_local(self):
        out, err = b.ollama_chat(self.cfg("claude_cli"), "sys", "what is on screen", images=["aGk="])
        self.assertNotEqual(out, "claude says hi")


if __name__ == "__main__":
    unittest.main()
