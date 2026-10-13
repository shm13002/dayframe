# Grok as a CLI provider: enums, runner, parsing
Status: ready-for-agent
Type: task

Add `.grok` to `ChatCLITool`, `LLMProviderID`, `DashboardChatProvider` and `DailyRecapProvider`, and handle it in every switch. Run it from `ChatCLIProcessRunner`: the prompt goes in through `--prompt-file`, JSON and streaming-JSON are parsed with usage, and the executable is resolved with a `~/.grok/bin/grok` fallback. Unit tests mirror `ClaudeCLIExecutionProfileTests` (arguments, envelope parsing, usage, missing session).
