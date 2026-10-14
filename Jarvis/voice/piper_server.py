"""Fast Piper voice for Jarvis. Alan stands in until a trained voice exists.

Loads the voice once and listens on 127.0.0.1:5056.
POST /tts {"text": a string of at most 400 characters} returns a WAV.
GET /health reports the voice. Any request with an Origin header is refused.
The bearer token lives in ~/jarvis-piper/service.token (mode 0600, created on first run).

`create_app` takes the synthesizer, so tests never load the ONNX model.
Run it with ~/jarvis-piper/.venv/bin/python.
"""

import io
import json
import os
import secrets
import time
import wave
from pathlib import Path

MAX_CHARS = 400
HOST = "127.0.0.1"
PORT = 5056
HOME = Path.home() / "jarvis-piper"
DEFAULT_VOICE = HOME / "voice" / "en_GB-alan-medium.onnx"


def create_app(synthesize, token, metadata):
    """A WSGI app. `synthesize(text)` returns WAV bytes or raises."""

    def app(environ, start_response):
        if environ.get("HTTP_ORIGIN"):
            return _json(start_response, 401, {"error": "Unauthorized"})
        expected = "Bearer " + token
        if not secrets.compare_digest(environ.get("HTTP_AUTHORIZATION", ""), expected):
            return _json(start_response, 401, {"error": "Unauthorized"})
        method = environ.get("REQUEST_METHOD", "")
        path = environ.get("PATH_INFO", "")
        if method == "GET" and path == "/health":
            body = {"ok": True}
            body.update(metadata)
            return _json(start_response, 200, body)
        if method == "POST" and path == "/tts":
            return _speak(environ, start_response, synthesize)
        return _json(start_response, 404, {"error": "Not found"})

    return app


def load_token(path):
    """Read the bearer token, creating a 0600 file the first time."""
    try:
        fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        pass
    else:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(secrets.token_urlsafe(32))
    os.chmod(path, 0o600)
    token = path.read_text(encoding="utf-8").strip()
    if len(token) < 32:
        raise RuntimeError("Invalid local service token")
    return token


def wav_bytes(voice, text):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wav_file:
        voice.synthesize_wav(text, wav_file)
    return buf.getvalue()


def main(argv=None):
    import argparse

    parser = argparse.ArgumentParser(description="Jarvis's fast Piper voice")
    parser.add_argument("--voice", default=str(DEFAULT_VOICE))
    parser.add_argument("--port", type=int, default=PORT)
    args = parser.parse_args(argv)

    from piper.voice import PiperVoice

    voice_path = Path(args.voice)
    voice = PiperVoice.load(voice_path)
    token = load_token(HOME / "service.token")
    metadata = {
        "engine": "piper",
        "voice": voice_path.stem,
        "standIn": voice_path.name.startswith("en_GB-alan"),
        "sampleRate": voice.config.sample_rate,
    }
    app = create_app(lambda text: wav_bytes(voice, text), token, metadata)
    from wsgiref.simple_server import make_server

    server = make_server(HOST, args.port, app)
    server.serve_forever()


def _speak(environ, start_response, synthesize):
    try:
        value = json.loads(_body(environ).decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return _json(start_response, 400, {"error": "Invalid request"})
    if not isinstance(value, dict) or set(value) != {"text"}:
        return _json(start_response, 400, {"error": "Invalid request"})
    text = value["text"]
    if not isinstance(text, str) or not text.strip() or len(text) > MAX_CHARS:
        return _json(start_response, 400, {"error": "Invalid speech parameters"})
    text = text.strip()
    started = time.monotonic()
    try:
        wav = synthesize(text)
    except Exception:
        return _json(start_response, 503, {"error": "Local speech generation failed."})
    elapsed = str(round((time.monotonic() - started) * 1000))
    return _bytes(
        start_response,
        200,
        wav,
        "audio/wav",
        [("X-Jarvis-Generation-Ms", elapsed)],
    )


def _body(environ):
    try:
        length = int(environ.get("CONTENT_LENGTH") or 0)
    except ValueError:
        length = 0
    if length <= 0 or length > 8000:
        return b""
    return environ["wsgi.input"].read(length)


def _json(start_response, status, payload):
    return _bytes(
        start_response, status, json.dumps(payload).encode("utf-8"), "application/json", []
    )


def _bytes(start_response, status, payload, content_type, extra):
    start_response(
        "%d %s" % (status, _REASON[status]),
        [
            ("Content-Type", content_type),
            ("Content-Length", str(len(payload))),
            *extra,
        ],
    )
    return [payload]


_REASON = {
    200: "OK",
    400: "Bad Request",
    401: "Unauthorized",
    404: "Not Found",
    503: "Service Unavailable",
}


if __name__ == "__main__":
    main()
