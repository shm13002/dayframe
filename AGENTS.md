# Dayframe: rules for agents

Dayframe is a personal macOS app forked from Dayflow (MIT). It records the screen, turns it into a timeline with local or plan-based AI, and adds Briefing, the notch island and Start of day.

`START-HERE.md` is the human guide (layout, commands, where to change what). This file is how to work here.

## Before you change anything

1. Read the newest entries in `CHANGELOG.md`: it is the handoff log between sessions.
2. Read `CONTEXT.md` and use its words in code, tests, tickets and log entries.
3. Read the `docs/adr/` records that touch the area. If your change contradicts one, say so before doing it.

## The iteration loop

Every change is one small, finished slice:

1. **Ticket.** Work from a ticket in `.scratch/` (see Agent skills below), or write one first.
2. **Red, then green.** Logic that decides something (gates, layouts, parsers, timelines, colors) lives in a pure type with unit tests at its interface (`WelcomeEventGate`, `WindowSlot.frame(in:)` and `frameAt()` are the model). Write the failing test first.
3. **Clean.** Run `./check.sh` until it prints `all clean`. Add `--app` when Swift changed (it builds and runs the unit tests; needs about 3 GB free).
4. **Log.** Add a `CHANGELOG.md` entry (template at the top of that file) with the real time from `date "+%H:%M"`. Under **Checked**, write what you actually ran and saw, and name anything not yet verified.
5. **Commit.** One commit per entry, with the entry's title as the subject. The pre-commit hook runs `./check.sh --staged` and refuses unlogged or unclean commits.

After a fresh clone, turn the hook on once: `git config core.hooksPath .githooks`.

## Code standards

- **Swift:** formatted with `xcrun swift-format format -i <file>` (config: `.swift-format`, Apple's defaults, the same style Dayflow uses). Dayframe files carry zero warnings. In Dayflow's own files, touch only what the change needs, so upstream diffs stay small.
- **TypeScript (`Web/`):** strict `tsc`, Prettier (`npm --prefix Web run format`), Vitest tests next to the code as `*.test.ts`.
- **Python (`Briefing/`):** stdlib only; `unittest` tests in `Briefing/tests/`.
- **Deep modules:** give callers a small interface and keep the complexity inside. One value lives in one place; when Swift and the web page must share one (palette stops, show timings), one side sends it to the other, or a test pins the two together.
- **Logging:** use `os.Logger(subsystem: "local.dayframe.app", category: <area>)`, and log every decision a person might later ask about ("why didn't it play?"). Read them with `./logs.sh` (it calls `/usr/bin/log`, because in zsh plain `log` is a builtin that does nothing). Active categories: `welcome`, `startofday`, `wallpaper`, `island`, `notice`, `briefing`, `recording`, `usage`; give each new area its own category.
- **Settings keys:** `dayframe…` strings in a `Keys` enum on the type that owns them.

## Guardrails

- Keep how `build-and-install.sh` signs the app exactly as it is (ADR 0002). Recording depends on it.
- Ollama: send `reasoning_effort: "none"` and leave `num_ctx` unset (ADR 0004).
- Privacy settings (`tccutil`, System Settings toggles) are the user's to change. Tell them the command.
- Deploy Briefing changes with `cd ~/Documents/Projects/Dayframe/Briefing && ./install.sh` (or `./build-and-install.sh` when only `Web/` changed).
- The disk is nearly full. Check `df -h ~` before a build and stop if under 3 GB (unless running an incremental build with `DAYFRAME_LOW_DISK_OK=1` and 1 GB+ free).

## Agent skills

### Issue tracker

Tickets are local markdown files under `.scratch/<feature>/issues/`. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default roles (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`), written as a `Status:` line. See `docs/agents/triage-labels.md`.

### Domain docs

Single context: `CONTEXT.md` plus `docs/adr/` at the root. See `docs/agents/domain.md`.
