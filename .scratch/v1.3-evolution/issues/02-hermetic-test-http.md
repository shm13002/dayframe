# Hermetic in-process HTTP fallback for Briefing tests
Status: done
Type: task

Add `start_http_server` / `_InProcessHTTPServer` to `Briefing/tests/mocks.py` and wire `test_briefing.py` and `test_hardening.py` so all 104 Briefing unit tests run cleanly even when `socket.bind` is blocked by a sandbox.
