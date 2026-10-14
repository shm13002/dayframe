# Jarvis handoff (updated 2026-10-14 16:10, Claude → next AI)

Read this first. Then read `AGENTS.md` (how to work here), the top of `CHANGELOG.md`, `HERALD-MAP.md` (this folder) and the ticket `.scratch/jarvis/issues/10-fast-jarvis-voice.md`.

**Where we stopped:** in the middle of ticket 10, the fast Piper Jarvis voice. Gate 1 (Piper speed) passed. Gate 2 (can this Mac train Piper fast enough?) looks like a **fail on the Mac GPU**. The CPU hasn't been measured yet. Nothing in the app has changed for ticket 10 so far. The section "Ticket 10: where it stands" below has the numbers and the exact next steps.

## What Jarvis is

Dayframe (the owner's Mac app: screen timeline, Briefing and the notch island) was renamed **Jarvis**. The rename is display only. The bundle ID `local.dayframe.app`, `dayframe://`, the settings keys and the data folder are unchanged.

Jarvis became the owner's chief-of-staff agent by putting **Herald OS v0.1.0-alpha.4**'s capabilities on top of **Hermes Agent** (Nous Research).

- **Installed:** `/Applications/Jarvis.app` v1.4 (tag `v1.4`, commit `efcb870`).
- **Backup:** `~/Documents/Projects/Dayframe Versions/v1.4 (2026-10-14)/`.
- **Roadmap plan:** `~/.claude/plans/okay-now-that-we-swift-lovelace.md`. Chunk 1 is done; chunks 2–5 are still to do.
- **Ticket 10 plan, approved by the owner:** `~/.claude/plans/read-this-and-continue-happy-tiger.md`. Its steps are also written out below.
- **Tickets:** `.scratch/jarvis/issues/`.

## How it fits together

| Piece | Where |
|---|---|
| Starts and watches `hermes serve` (random port + token, `HERALD_OS=1`) | `App/Dayflow/Core/Jarvis/HermesBackend.swift` |
| Long-lived Jarvis page, voice, notch eyes, ⌥Space | `Core/Jarvis/JarvisCoordinator.swift`, `JarvisVoice.swift`, `JarvisListener.swift`, `JarvisHotKey.swift` |
| Jarvis tab (first in the sidebar; the HQ) | `Views/UI/Jarvis/JarvisView.swift` hosts `Web/src/jarvis` (React), built into `App/Dayflow/Jarvis/Resources/jarvis.html` and loaded from file:// |
| Hermes gateway client | `Web/src/jarvis/hermes/upstream/` (vendored unchanged; don't edit) |
| System tools with approval tiers and an audit log | `Jarvis/bridge/herald-os-bridge` (from Herald, MIT). Changes are listed in `Jarvis/bridge/JARVIS-CHANGES.md`. Installed by `Jarvis/install-bridge.sh`, which **copies** it to `~/.hermes/plugins` |
| Piper voice training wrapper (new, ticket 10) | `Jarvis/voice/train.py` |
| Settings › Jarvis | `Views/UI/Settings/JarvisSettingsView.swift` |
| Hermes install, config, sign-ins | `~/.hermes` (model `xai-oauth` / `grok-4.6`) |
| Jarvis's audit log and permission policy | `~/.hermes/herald-os/` |

## Owner's decisions (don't ask again)

- **Brain:** Grok is the fast default; ChatGPT and Claude can be switched in; Qwen is only the offline fallback. No API keys.
- **Look and feel:** Grok Bot's quick feel, with Dayframe's palette and brand. Keep the Dayframe icon.
- **Speed:** never slower than Herald, whose voice starts speaking about 1 s after the reply begins.
- **Voice:** speak a one-sentence summary, not whole answers. The owner chose to **train a fast Piper Jarvis voice** plus the phrase cache.
- **Ticket 10 choices (2026-10-14):**
  - **Base voice:** start from **Alan** (`en_GB-alan-medium`, RP accent). The owner listened to both stock voices and picked it.
  - **Dataset run:** overnight, or while the owner is away. Smoke-test on 5 lines first.
  - **Disk:** caches that rebuild themselves may be cleared, but list them and get an OK first.
- **Ask the owner before every download**, giving name, source and size.
- **Off limits:** the Jarvis HQ spec, the GenUI kit and the `DayFrameJarvis` package belong to a separate Codex project.
- **`~/jarvis-voice`** may be changed, but another agent (Codex) edits it too. Never edit `tts_server.py`; build beside it.

## Ticket 10: where it stands

**Goal:** live answers speak in the Jarvis voice within 1 s. Today they use the phrase cache plus a British Mac voice, because the cloned OmniVoice voice (`~/jarvis-voice`, 127.0.0.1:5055) takes about 50 s per sentence.

### Done

1. **Disk:** the owner approved and emptied Cursor's staged update (970 MB) and Chrome's web cache (900 MB). Free space was 9–14 GB at 16:10, but it swings with swap.
2. **Workspace `~/jarvis-piper/`** (outside ~/Documents on purpose, because of TCC):
   - `.venv`: Python 3.11 (uv) with `piper-tts==1.8.0[train]` (the version Hermes pins) and torch 2.8.0 (from the uv cache).
   - `stock/`: `en_GB-alan-medium.onnx` and `en_GB-northern_english_male-medium.onnx`, with their `.json` files.
   - `bench/`: the benchmark WAVs and the comparison clips the owner listened to.
   - `probe/`: 24 placeholder clips made by Alan, `metadata.csv`, and the probe logs.
   - `src/core.pyx`.
3. **Gate 1, Piper speed: PASS.**
   - A one-sentence summary synthesizes in a median of 0.29–0.44 s and at most about 0.8 s. That was measured with load average 11 and 10 GB of swap.
   - Model load takes 2–9 s, so a long-lived server is needed (load once).
   - `bench_piper.py` was a scratch script; the numbers above are what it printed.
4. **Monotonic_align built:** the piper 1.8.0 wheel ships without `core.pyx`. It was fetched from `OHF-Voice/piper1-gpl` tag `v1.8.0` and built in place. The `.so` lives in `.venv/lib/python3.11/site-packages/piper/train/vits/monotonic_align/monotonic_align/`.
5. **`Jarvis/voice/train.py`:** a wrapper around `python -m piper.train fit`. It:
   - keeps **only `last.ckpt`**: Piper's defaults keep up to 11 checkpoints of 846 MB each, which would fill the disk
   - logs every training step's time and peak memory to `--steps-log`
   - turns the MOS metric off, because it would download UTMOS through torch.hub
6. **Gate 2, training speed on the Mac GPU (MPS): looks like a FAIL.**
   - Measured with batch 8 at 16:06–16:08 (`~/jarvis-piper/probe/steps-mps.log`):
     - 19.2, 16.8, 82.5 and 28.0 s per batch. The 82 s batch includes the end-of-epoch validation.
     - Peak memory was 937 MB.
   - Estimate for 400 clips at batch 8: 50 batches × ~20 s ≈ **17 min per epoch**. So 100 epochs ≈ 28 h, and a typical fine-tune of several hundred epochs would take days.
   - The run was stopped on purpose, so the owner could switch AIs.

### Next steps for ticket 10, in order

**1. Finish gate 2.**
- Run the same probe on the CPU, from `~/jarvis-piper`, with nothing else heavy running:
  ```bash
  .venv/bin/python ~/Documents/Projects/Dayframe/Jarvis/voice/train.py --steps-log probe/steps-cpu.log --checkpoint-every 0 fit --data.voice_name probe --data.csv_path probe/metadata.csv --data.audio_dir probe/wavs --model.sample_rate 22050 --data.espeak_voice en-gb-x-rp --data.cache_dir probe/cache --data.config_path probe/config.json --data.batch_size 8 --trainer.max_epochs 4 --trainer.accelerator cpu --trainer.logger false --trainer.default_root_dir probe/run-cpu
  ```
- Also try MPS with batch 16 or 32 (memory allowing). The time per batch may grow less than the batch does.
- **Gate:** the estimated fine-tune (≈400 clips) takes ≤ about 24 h.
- **If both fail,** stop and give the owner the measured options. Don't switch approach silently. Examples:
  - **(a)** NeuTTS Air instant cloning from the ~12 s reference `~/jarvis-voice/ref32_combo.wav` (Hermes ships a `neutts` extra). Benchmark its first-audio time first.
  - **(b)** Train on a rented cloud GPU. This uploads the voice dataset, so it needs the owner's OK.
  - **(c)** A much shorter fine-tune (about 50–150 epochs), accepting lower quality.
  - **(d)** Fewer clips.

**2. Sentences** (`Jarvis/voice/sentences.txt`).
- About 420 lines: 400 for training and 20 held out. Generate them with Hermes/Grok (`~/.local/bin/hermes -z "<prompt>"`, run from a folder with no AGENTS.md), then review.
- Ask the owner before running Hermes: on 2026-10-14 the owner stopped this command before it ran.
- Three batches of 150 worked well as a design:
  - (a) operating the Mac: files, apps, memory, disk, network, approvals
  - (b) Shahzeb's day: greetings, briefings, dates and times, people, the weather
  - (c) phonetically rich general English: rare sounds, names, numbers, abbreviations
- Lines are 3–25 words, British spelling, plain text. Include all 18 `JarvisVoice.commonPhrases`.
- A pure `clean_lines()` (dedup, length, ≤ 400 characters) with stdlib `unittest` tests that run on the system `python3` 3.9.

**3. Dataset builder** (`Jarvis/voice/make_dataset.py`, stdlib only).
- Posts each line to `http://127.0.0.1:5055/tts`:
  - body `{"text","voice":"jarvis","steps":32}`
  - header `Authorization: Bearer <~/jarvis-voice/service.token>`
  - **no Origin header**

  This is exactly what `JarvisVoiceClient.wav(for:)` in `JarvisVoice.swift` sends.
- Resumable: it skips WAVs that already exist. On 429 (busy, shared with Codex's app) it waits 30 s. It waits about 5 s between lines.
- Writes `~/jarvis-piper/dataset/wavs/NNNN.wav` and `metadata.csv` (`NNNN.wav|text`), and logs `X-Jarvis-Generation-Ms`.
- Reuses the cached phrase WAVs in `~/Library/Application Support/Dayflow/Jarvis/voice-cache`. Their key is the SHA-256 of the normalized text (see `JarvisPhraseCache.key`).
- The WAVs stay at 24 kHz: Piper's loader resamples them to 22,050 Hz with librosa.
- Smoke-test 5 lines. The full run takes about 5–6 h (`nohup caffeinate -i …`), started overnight with the owner's OK.

**4. Fine-tune** (after the dataset is complete; never while OmniVoice is generating).
- **Ask, then download** Alan's checkpoint from `huggingface.co/datasets/rhasspy/piper-checkpoints`: `en/en_GB/alan/medium/epoch=6339-step=1647790.ckpt` (845,898,392 bytes).
- Run `train.py --checkpoint-every 5 fit` with:
  - `--data.espeak_voice en-gb-x-rp` (**not** `en-gb`, which fails in Piper's bundled espeak)
  - `--model.sample_rate 22050`
  - a batch size from the probe
  - `--trainer.max_epochs N`
  - `--trainer.default_root_dir <run dir>`
  - `--ckpt_path <alan ckpt>`
- Listen to sample lines at checkpoints.

**5. Export and quality gate.**
- Export: `python -m piper.train.export_onnx --checkpoint … --output-file ~/jarvis-piper/voice/en_GB-jarvis-medium.onnx`, plus the training config as `en_GB-jarvis-medium.onnx.json`.
- On the 20 held-out lines, at least 19 must pass Whisper intelligibility. Use `intelligible()` from `~/jarvis-voice/verification.py`, running in that folder's venv (import it; never edit it).
- The owner listens to the cloned voice against Piper. Shipping is the owner's call.
- After asking, delete the checkpoints and the cache.

**6. Server and Swift.** This can be built earlier, with Alan standing in.

- **`Jarvis/voice/piper_server.py`:**
  - Loads the voice once and listens on 127.0.0.1:**5056**.
  - Bearer token in `~/jarvis-piper/service.token` (0600, created on first run). Refuses any request with an Origin header.
  - `POST /tts {"text"}` (≤ 400 chars) returns a WAV and `X-Jarvis-Generation-Ms`. `GET /health` reports status.
  - Built as an injectable `create_app` with tests, like `tts_server.py`.
- **Install:**
  - LaunchAgent `local.jarvis.piper`.
  - `Jarvis/voice/install-voice.sh` copies the server and the voice to `~/jarvis-piper`.
  - `build-and-install.sh` calls it only once a trained voice exists.
  - Add a `check_jarvis_voice` section to `check.sh`, modeled on `check_jarvis_bridge`.
- **Swift** (`JarvisVoice.swift`):
  - `JarvisVoiceClient` gets an engine setting. Piper uses port 5056, `{"text"}`, a 3 s timeout and no retries.
  - A pure, tested `JarvisVoiceRoute.steps(mode:)`:
    - `.live` → cache, Piper, Mac voice
    - `.notice` → cache, cloned voice, Piper, Mac voice
  - `Source.piperVoice` is added.
  - Each spoken piece logs its engine and its first-audio ms (from `speak()` to `play()`).
- **Settings › Jarvis:** a "Fast Jarvis voice" row, and new wording for the voice text.
- **Checks:** `swift-format`, then `./check.sh --app`.

**7. Measure and close.**
- In the installed app: Settings › Jarvis › Test, plus 10 one-sentence lines. Read first-audio ms with `./logs.sh`. **Target: median and max ≤ 1 s.**
- Then:
  - set the ticket to `Status: done`
  - add the CHANGELOG entry and commit
  - update this file
  - save v1.5 only with the owner's OK
- **Needs the owner:** a real ⌥Space voice turn.

## After ticket 10 (roadmap)

1. **Chunk 2, presence and speed:**
   - study Grok Bot's UX (ask before screen access)
   - a quick floating panel under the notch
   - a "Hey Jarvis" wake word
   - the control socket and command registry, so Jarvis can operate its own UI (Herald's `os_ui`)
2. **Chunk 3, HQ pages:**
   - Missions
   - Memory (Hermes + Briefing)
   - Automations (Hermes cron + event triggers + Briefing automations)
   - Connections (MCP, messaging)
   - Usage
3. **Chunk 4, Mac depth:**
   - crash help
   - screen tools (OCR, QR codes, asking about a region)
   - dictation
   - app installs
   - a system monitor

## Not yet verified (needs the owner at the Mac)

- A real ⌥Space voice turn. The ChatGPT app may own ⌥Space; Settings › Jarvis shows whether it registered.
- The Jarvis tab UI in person.

## Gotchas

- **Another app is called "Jarvis":** Codex's Electron app at `~/Applications/Jarvis.app` (`local.jarvis.desktop`). Never `pkill -x Jarvis` or `pgrep -x Jarvis`; match `^/Applications/Jarvis.app/Contents/MacOS/Jarvis`.
- **Signing:** never change it (ADR 0002); the Screen Recording permission depends on it.
- **Recording pauses while the screen is locked,** by design.
- **Island sounds** must stay on AVAudioPlayer. AVAudioPlayerNode crashed the app on screen lock.
- **`hermes mcp add`** cancels on a closed stdin: pipe `y`.
- **Memory and disk are linked.** This Mac has 16 GB of RAM and swap reached 11 GB, which shrank free disk to 0.6 GB. The big users:
  - Ollama `qwen3.5:4b`, 7–8.5 GB while loaded (Dayframe's timeline model; it unloads after its keep-alive)
  - the OmniVoice server, about 3.9 GB
  - Chrome, Cursor, Codex, Grok Bot

  Check `df -h ~` and `sysctl vm.swapusage` before any long job. Builds need 3 GB.
- **Piper training traps (1.8.0):**
  - The wheel lacks `monotonic_align/core.pyx` (already fixed in the venv).
  - The espeak voice must be `en-gb-x-rp`.
  - Default checkpoint callbacks keep about 11 × 846 MB (use `train.py`).
  - The default MOS metric downloads UTMOS.
  - LightningCLI refuses to start if `config.yaml` exists in its root dir: give every run its own `--trainer.default_root_dir`.
- **Orphaned test processes:** kill throwaway `hermes serve` backends (ppid 1) and any `Jarvis/voice/train.py` probe you start.
- **Hermes's installer** also added `ai.hermes.gateway`. Ask before removing it.
- **Every change** needs a dated `CHANGELOG.md` entry and one commit; the pre-commit hook runs `./check.sh --staged`.
- **Saving a version:** tag + backup folder + bump `MARKETING_VERSION` / `CFBundleShortVersionString`. A GitHub push needs `gh auth login` first.
