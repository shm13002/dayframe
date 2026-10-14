# HermesBackend: find, start, watch and stop hermes serve
Status: done
Type: task

Swift port of Herald electron/backend: HermesLocator (env, ~/.hermes/hermes-agent, PATH), HermesReadyLine parser, restart backoff 1/3/7/15 s, /api/status probe, SIGTERM on quit. Env: random token, HERMES_DESKTOP=1, HERALD_OS=1. Pure parts unit-tested.

## Comments
- 2026-10-14 12:26: built and unit-tested (CHANGELOG 12:26). Live end-to-end check waits on 03 (Hermes sign-in).
