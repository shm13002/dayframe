# Grok connections

The user wants Grok connected "just like Claude", in three ways:

1. **Grok as a CLI provider** for timeline cards, Chat and the daily recap, chosen in Settings › Providers. It runs xAI's Grok CLI (`~/.grok/bin/grok`, signed in through grok.com, no API key; see ADR 0003) headless: `grok -p … --output-format json|streaming-json`.
2. **Briefing can write with Grok:** a `grok_cli` value for `llm_backend`, next to claude_cli and codex_cli, with the same fallback to Qwen.
3. **Grok can read Dayframe:** register Dayframe's MCP server with the Grok CLI (`~/.grok/config.toml`) in Settings › MCP / CLI, and with the Grok Bot desktop app if it takes MCP servers.

Facts (Grok CLI 0.2.99): JSON output is `{text, sessionId, usage:{input_tokens, cache_read_input_tokens, output_tokens, reasoning_tokens}}`. Streaming emits `text`/`thought`/`end`/`error` lines, and the session id only arrives in `end`. There is no `--image` flag, and the prompt can't come on stdin (use `--prompt-file`). Resume with `-r <id>`. Models (cached July list): `grok-4.5` (effort low/medium/high), `grok-composer-2.5-fast`.
