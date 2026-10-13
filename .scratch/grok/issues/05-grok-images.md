# Give Grok the screenshots, not just their text
Status: needs-info
Type: research
Blocked by: 01, 02

Grok transcribes from on-screen text only, because its headless mode documents no image input. Once `grok login` is done, test whether `--prompt-json` accepts image content blocks (or `read_file` on a PNG reaches the model). If one does, switch transcription to images like Codex.
