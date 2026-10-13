# AI runs locally or through the user's own plans, never API keys

Providers are local Ollama (Qwen 3.5 by default) or CLI providers that run a command-line agent already signed in with the user's subscription (Claude Code, Codex, Grok). The user explicitly said no API keys. Dayflow's hosted services (Dayflow Pro, Gemini key flow) and its telemetry (Sentry, PostHog) and updater (Sparkle) are removed and replaced with no-op stubs. A new provider must follow the same pattern: find the CLI, check that it is signed in, and run it headless.
