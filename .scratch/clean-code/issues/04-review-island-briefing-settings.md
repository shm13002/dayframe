# Review the rest of Dayframe's code (island, native Briefing, settings, chat on Qwen)
Status: done
Type: task

A standards and smell review (Matt's code-review baseline: duplicated code, mysterious names, repeated switches, speculative generality, middle men, force casts, swallowed errors, unlogged decisions) of everything in `git diff 1df9be4 -- App/` outside `App/Dayflow/Welcome`. Fix what's real, and record what's deliberate.

## Comments

- 2026-10-13 14:15: done (CHANGELOG 14:15). Fixed: swallowed Briefing action errors (now a banner and a log line), the duplicated Briefing port, print → Logger, unlogged show and usage failures, repeated pill hex colors. Kept on purpose: sleep/decoder `try?`, force unwraps of constant URLs and the standard audio format, and Dayflow-owned files.
