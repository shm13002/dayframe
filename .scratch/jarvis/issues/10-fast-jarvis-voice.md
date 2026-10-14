# A fast Jarvis voice (Piper), so live answers speak in the Jarvis voice at once
Status: claimed
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

**2026-10-14 17:46. Alan is the filler voice in the app.** The owner stopped the training-speed work. Live speech is the phrase cache, then Alan (Piper on 127.0.0.1:5056), then the Mac voice. "On it." synthesized in 292 ms. Gate 2 (CPU training) was not measured. The ticket stays open until a real ⌥Space turn is checked and, later, a trained voice replaces Alan.

**2026-10-14 16:10 (Claude), paused for a switch to another AI.** Full state and next steps: `docs/jarvis/HANDOFF.md`.
- **Owner's choices:** start from the Alan voice (`en_GB-alan-medium`, RP); run the dataset overnight; clear caches only with an OK.
- **Workspace:** `~/jarvis-piper/` (venv with `piper-tts==1.8.0[train]` + torch 2.8, the stock voices, benchmark and probe files).
- **Gate 1, speed: PASS.** A one-sentence summary synthesizes in a median of 0.29–0.44 s (max about 0.8 s) under heavy load. Model load takes 2–9 s, so a long-lived server is needed.
- **Gate 2, training on MPS: likely FAIL.** It took 17–28 s per batch of 8 (`~/jarvis-piper/probe/steps-mps.log`), about 17 min per epoch for 400 clips. The CPU probe hasn't run yet. If the CPU fails too, offer the owner the options listed in the handoff. Don't switch silently.
- **Added `Jarvis/voice/train.py`:** keeps only `last.ckpt`, logs each step's time, and turns MOS off.

**2026-10-14 18:03. Owner deferred gate 2 at 17:02. Alan is the filler. Ticket stays open.**
- Do not run the CPU or MPS training probes unless the owner asks. Do not generate sentences, do not call OmniVoice for a dataset, and do not fine-tune.
- Alan (`~/jarvis-piper/stock/en_GB-alan-medium.onnx`) is served by `Jarvis/voice/piper_server.py` on 127.0.0.1:5056 (LaunchAgent `local.jarvis.piper`). "On it." was 860 ms cold and 292 ms on the next call.
- The installed app was rebuilt the same evening (still version 1.4, not tagged). Live is cache, then Piper, then the Mac voice. Notices try the cloned voice before Piper. `Source.piperVoice` is logged with first-audio ms from `speak()` to `play()`.
- Still open: a trained Jarvis voice, the 1 s check inside the installed app, and a real ⌥Space turn.
