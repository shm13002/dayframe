# Jarvis speaks with the Jarvis voice
Status: ready-for-agent
Type: task

JarvisVoice: sentence splitter (<=400 chars), client for 127.0.0.1:5055/tts (bearer from ~/jarvis-voice/service.token, no Origin), serial queue, 429 retry, 422 skip, AVSpeechSynthesizer fallback when the server is down. Unit tests against a stub.

## Comments
