# Briefing: grok_cli backend
Status: ready-for-agent
Type: task

Add `grok_cli` to briefing.py next to claude_cli/codex_cli: add `~/.grok/bin` to the CLI search folders, pass the prompt without stdin, parse usage, fall back to Qwen on auth errors. Tests mirror `test_cli_backend.py`. Add the choice to the Briefing writer picker (native and React).
