# HermesBackend: find, start, watch and stop hermes serve
Status: ready-for-agent
Type: task

Swift port of Herald electron/backend: HermesLocator (env, ~/.hermes/hermes-agent, PATH), HermesReadyLine parser, restart backoff 1/3/7/15 s, /api/status probe, SIGTERM on quit. Env: random token, HERMES_DESKTOP=1, HERALD_OS=1. Pure parts unit-tested.

## Comments
