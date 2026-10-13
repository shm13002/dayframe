# Tests must never act on the real Mac
Status: done
Type: task

The user saw a "Where you left off" dialog and GitHub 404 tabs on every test run. Briefing's tests reached real `osascript`/`open` calls. Fixed with one `run_on_mac()` entry point plus a tripwire in `tests/mocks.py`. See CHANGELOG 2026-10-13 11:08.

## Comments

- 2026-10-13 11:08: done.
