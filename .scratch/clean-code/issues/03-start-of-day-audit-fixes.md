# Start of day: audit fixes
Status: done
Type: task

Findings from auditing commit 0c28ded:
1. Show timings live in two places: `WelcomeShowPanel` hard-codes 5.45 / 2.0 / 0.8 s, and `scene.ts` has `DURATION`/`REDUCED_DURATION`. The page should send its duration with "started".
2. `WelcomeShowPanel` finds the main display's panel by searching subviews for a WKWebView, twice. Keep a reference instead.
3. The login and unlock decisions aren't logged, so "why didn't it play?" can't be answered after a real login or lock. Log each decision and its inputs (category `welcome`).
4. `WelcomeController.start()` also starts `WallpaperManager`, a hidden coupling. AppDelegate should start each one.
5. `StartOfDay.placeDayframe()` moves the first visible main-capable window, which can be Settings. It should move the main window.
6. `StartOfDay` counts apps that were already running as "opened", and `try?` swallows launch failures. Report opened / already open / failed, and log each app.
7. `AXWindowPlacer.firstWindow` force-casts (`as!`). Check the CF type instead.
8. `testWallpaperRendersAtNativeSizeForEveryPalette` writes 12 full-size PNGs into tmp on every run. Only write them when asked (env var).
9. `WelcomeEventGateTests` now also covers slots and the wallpaper. Name the file after what it tests.
10. `WindowStyleSection` creates a `Timer.publish` in a view struct. Use a `.task` loop.
11. The CHANGELOG 23:34 entry lists `SettingsOtherTabView.swift`, which the commit didn't touch, and says "Commit: see git log". Correct it to `0c28ded`.
12. Add a shell trigger for the welcome preview (`dayframe://welcome/preview?variant=…`) so its in-app fps can be measured and logged without computer control.

## Comments

- 2026-10-13 11:35: done (CHANGELOG 11:35). All 12 findings fixed; also found and fixed the external-display cover bug. 227 app tests green.
