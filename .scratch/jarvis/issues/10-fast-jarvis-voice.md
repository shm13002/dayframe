# A fast Jarvis voice (Piper), so live answers speak in the Jarvis voice at once
Status: ready-for-agent
Type: task

The cloned voice (`~/jarvis-voice`, OmniVoice, 32 steps + Whisper check) takes ~50 s per sentence on this
Mac (measured 2026-10-14: 42.8 s and 52.0 s). Live answers therefore use the phrase cache (Jarvis voice)
plus the best British Mac voice. The owner chose: **train a Piper voice + phrase cache**.

Plan:
1. Benchmark first (stock Piper en_GB voice speed; NeuTTS as a fallback). Ask the owner before EVERY download
   (Piper, espeak-ng, starting checkpoint ~100–500 MB); check `df -h ~` (need several GB).
2. Dataset: 300–500 varied sentences (generate the text with Hermes/Grok), synthesized by the OmniVoice
   server in the background only when it is idle (it is shared with Codex's Jarvis app; 429 = busy, wait).
3. Fine-tune Piper from an English checkpoint; export ONNX; add a `piper` engine to `JarvisVoice`
   (`.live` → cache → Piper → Mac voice). Hermes also lists piper as a TTS provider.
4. Measure first-audio latency; it must be ≤ Herald's (~1 s).

Owner said `~/jarvis-voice` may be changed, but on 2026-10-14 12:45 another agent (likely Codex) edited
`tts_server.py` (pinned MODEL_REVISION), so leave the server file alone and build beside it.

## Comments
