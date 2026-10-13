# Qwen on Ollama: no thinking, 4096-token context, never send num_ctx

Qwen 3.5 thinks by default, and `think: false` is ignored on Ollama's OpenAI-compatible `/v1` API, so every request sends `reasoning_effort: "none"`. Ollama serves Qwen with a 4096-token context. Sending `num_ctx` makes it reload the model, which on this 16 GB Mac stalls the timeline. Chat therefore keeps tool results compact (one line per card, 6k-character cap) and sends only the last 6 messages.
