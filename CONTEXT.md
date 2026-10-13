# Dayframe

A personal Mac app that records your day, explains it back to you and opens your day for you. Forked from Dayflow; the Swift module is still called `Dayflow`.

## Language

### Recording and the timeline

**Recording**:
The screen capture that runs all day, stored as chunks in the shared Dayflow data folder.
_Avoid_: capture session, screen log

**Batch**:
A span of recording sent to the AI at once to be turned into cards.
_Avoid_: job, chunk group

**Card**:
One block of the timeline: a titled activity with a start, an end and a category.
_Avoid_: entry, activity card (in UI copy), event

**Timeline**:
The day's cards in order. The main screen of the app.

**Watchdog**:
The in-app check that restarts recording when frames stop arriving.

**Keep-alive**:
The LaunchAgent (`local.dayframe.keepalive`) that reopens Dayframe and Ollama if they quit.

### AI

**Provider**:
Where the AI runs for cards, Chat and summaries: local Ollama (Qwen), or a CLI provider.
_Avoid_: backend (except in Briefing's `llm_backend` setting), engine

**CLI provider**:
A provider that runs a command-line agent signed in with the user's own plan (Claude Code, Codex, Grok). No API keys.
_Avoid_: API provider, cloud provider

**Chat**:
Asking questions about your day; answered with tools that read the timeline.

### Briefing

**Briefing**:
The morning-to-evening summary screen (next thing, loops, today strip, focus, ask), served by `briefing.py` and shown as a sidebar tab.
_Avoid_: dashboard (that is Briefing's older web page), report

### Notch island

**Island**:
Everything Dayframe draws at the notch: the pill, shows and moments.

**Pill**:
The always-on shape around the notch: focus ring and percent on the left, Jarvis's eyes and tracked time on the right.

**Show**:
A full-screen animation that plays once and closes. The island's startup show and the welcome are both shows.
_Avoid_: overlay, splash

**Moment**:
A short island reaction to an event (new card, focus goal reached, pause, end of day).

### Start of day

**Welcome**:
The opening show, Dayframe's rebuild of the Aether Pulse "System Awakening". It has two cues.
_Avoid_: intro, splash, launch video

**First launch** (cue):
The full 5.4-second welcome, played once per login session.

**Daily wake** (cue):
The two-second welcome played after an unlock when you were away long enough.

**Login session**:
One macOS login, identified by `CGSSessionUniqueSessionUUID`. The first-launch cue plays at most once per login session.

**Start of day**:
What runs after the first-launch cue: Dayframe opens on Briefing, the day apps open, windows go to their slots and other apps are hidden.

**Day apps**:
The apps the user chose to open at the start of the day.

**Slot**:
Where a window goes on its display (left half, right third, centered…).

**Window style**:
Layout (Dayframe places windows in slots) or Stage Manager (macOS arranges them).

**Wallpaper**:
The textless desktop picture Dayframe renders from the palette. It also shows behind the lock screen.

### Look

**Palette**:
One of six named color sets (Original, Lagoon, Lavender, Matcha, Rose, Ember) that every surface follows. Original is Dayflow's own colors and the default.
_Avoid_: theme (that is light/dark appearance)
