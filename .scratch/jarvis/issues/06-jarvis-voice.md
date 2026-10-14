# Jarvis speaks with the Jarvis voice
Status: done
Type: task

JarvisVoice: sentence splitter (<=400 chars), client for 127.0.0.1:5055/tts (bearer from ~/jarvis-voice/service.token, no Origin), serial queue, 429 retry, 422 skip, AVSpeechSynthesizer fallback when the server is down. Unit tests against a stub.

## Comments
- 2026-10-14 12:26: built and unit-tested (CHANGELOG 12:26). Live end-to-end check waits on 03 (Hermes sign-in).
