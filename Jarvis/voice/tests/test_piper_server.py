"""The Piper server's request rules, with no ONNX model loaded."""

import io
import json
import stat
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import piper_server


def call(app, method, path, body=None, headers=None):
    raw = body.encode("utf-8") if isinstance(body, str) else (body or b"")
    environ = {
        "REQUEST_METHOD": method,
        "PATH_INFO": path,
        "SERVER_NAME": "127.0.0.1",
        "SERVER_PORT": "5056",
        "SERVER_PROTOCOL": "HTTP/1.1",
        "wsgi.version": (1, 0),
        "wsgi.url_scheme": "http",
        "wsgi.input": io.BytesIO(raw),
        "wsgi.errors": io.StringIO(),
        "wsgi.multithread": False,
        "wsgi.multiprocess": False,
        "wsgi.run_once": False,
        "CONTENT_LENGTH": str(len(raw)),
        "CONTENT_TYPE": "application/json",
    }
    for key, value in (headers or {}).items():
        environ["HTTP_" + key.upper().replace("-", "_")] = value
    captured = {}

    def start_response(status, response_headers, exc_info=None):
        captured["status"] = status
        captured["headers"] = dict(response_headers)

    payload = b"".join(app(environ, start_response))
    return captured["status"], captured["headers"], payload


class PiperServerTests(unittest.TestCase):
    def setUp(self):
        self.calls = []

        def synthesize(text):
            self.calls.append(text)
            return b"RIFF-wav"

        self.synthesize = synthesize
        self.app = piper_server.create_app(
            synthesize, "t" * 40, {"engine": "piper", "voice": "en_GB-alan-medium"}
        )
        self.auth = {"Authorization": "Bearer " + "t" * 40}

    def test_origin_is_refused_even_with_the_token(self):
        status, _, body = call(
            self.app,
            "POST",
            "/tts",
            '{"text": "On it."}',
            {**self.auth, "Origin": "http://evil"},
        )
        self.assertTrue(status.startswith("401"))
        self.assertEqual(self.calls, [])
        self.assertIn(b"Unauthorized", body)

    def test_a_bad_token_is_refused(self):
        status, _, _ = call(
            self.app, "GET", "/health", headers={"Authorization": "Bearer nope"}
        )
        self.assertTrue(status.startswith("401"))

    def test_health_reports_the_voice(self):
        status, _, body = call(self.app, "GET", "/health", headers=self.auth)
        self.assertTrue(status.startswith("200"))
        report = json.loads(body)
        self.assertTrue(report["ok"])
        self.assertEqual(report["voice"], "en_GB-alan-medium")
        self.assertEqual(report["engine"], "piper")

    def test_tts_returns_a_wav_and_the_generation_time(self):
        status, headers, body = call(
            self.app, "POST", "/tts", '{"text": "On it."}', self.auth
        )
        self.assertTrue(status.startswith("200"))
        self.assertEqual(headers["Content-Type"], "audio/wav")
        self.assertEqual(body, b"RIFF-wav")
        self.assertTrue(headers["X-Jarvis-Generation-Ms"].isdigit())
        self.assertEqual(self.calls, ["On it."])

    def test_only_a_short_text_field_is_accepted(self):
        for body in (
            '{"text": "%s"}' % ("word " * 90),
            '{"text": "   "}',
            '{"text": "Hi", "voice": "jarvis"}',
            "[]",
            "not json",
        ):
            status, _, _ = call(self.app, "POST", "/tts", body, self.auth)
            self.assertTrue(status.startswith("400"), body)
        self.assertEqual(self.calls, [])

    def test_a_failed_synthesis_is_503(self):
        def fail(text):
            raise RuntimeError("boom")

        app = piper_server.create_app(fail, "t" * 40, {})
        status, _, _ = call(app, "POST", "/tts", '{"text": "Hi"}', self.auth)
        self.assertTrue(status.startswith("503"))

    def test_token_file_is_created_private_and_reused(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "service.token"
            first = piper_server.load_token(path)
            mode = stat.S_IMODE(path.stat().st_mode)
            self.assertEqual(mode, 0o600)
            self.assertGreaterEqual(len(first), 32)
            self.assertEqual(piper_server.load_token(path), first)


if __name__ == "__main__":
    unittest.main()
