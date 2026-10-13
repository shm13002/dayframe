# Grok as a CLI provider: enums, runner, parsing
Status: done
Type: task

Add `.grok` to `ChatCLITool`, `LLMProviderID`, `DashboardChatProvider` and `DailyRecapProvider`, and handle it in every switch. Run it from `ChatCLIProcessRunner`: the prompt goes in through `--prompt-file`, JSON and streaming-JSON are parsed with usage, and the executable is resolved with a `~/.grok/bin/grok` fallback. Unit tests mirror `ClaudeCLIExecutionProfileTests` (arguments, envelope parsing, usage, missing session).

## Design (2026-10-13)

- **`GrokCLICommand`** (new, pure, unit-tested like `ClaudeCLIExecutionProfile`): builds the arguments. The prompt goes in a private 0600 file through `--prompt-file`, which is deleted after the run. Grok can't read stdin, and an argument is visible to other processes. Text-only turns (cards, recap) add `--max-turns 1`, `--disable-web-search`, `--no-subagents`, `--no-memory`, `--no-plan` and deny every tool. Chat allows only the shell (`run_terminal_cmd`, for sqlite3 on the timeline) with `--always-approve`, the same trust Claude and Codex chat get today.
- **`GrokCLIOutput`** (new, pure, unit-tested): parses the `json` envelope (`text`, `sessionId`, `usage`, or `{"type":"error","message"}`) and the `streaming-json` lines (`text`, `thought`, `end` carrying `sessionId`, `error`). Usage maps to `TokenUsage(input: input_tokens + cache_read_input_tokens, output: output_tokens)`.
- **Executable:** `~/.grok/bin/grok` when it exists, else `grok` on the login shell's PATH.
- **One card generator, two adapters:** Codex's streaming card loop has nothing Codex-specific except its model names, so it moves to `AgentCLISupporting` for any provider that supplies a model configuration. Codex and Grok both use it, and Claude keeps its own stricter path. This removes the copy Grok would otherwise need.
- **Transcription:** Grok's headless mode has no image input (no `--image`; `--prompt-json` image blocks are undocumented), so Grok transcribes from the on-screen text (Apple Vision OCR of the sampled frames). Images are a follow-up once a signed-in run can test `--prompt-json`.

## Comments

- 2026-10-13 13:42: done (CHANGELOG 13:42). 239 tests green. Live run waits for `grok login`.
