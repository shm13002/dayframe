# 12 — Known Risks and Unknowns

1. **Connected Folder Sandbox Boundary (`Observed`):**
   - In this session, only `/Users/shahzi/Documents/Projects/Dayframe Versions/v1.2 (2026-10-13)` was added to Connected Folders (`/Users/shahzi/Documents/Projects/Dayframe` and the parent `/Users/shahzi/Documents/Projects/Dayframe Versions` returned `Operation not permitted`).
   - **Mitigation:** The complete `v1.3 (2026-10-13)` release package (`v1.3 (2026-10-13)/` containing `Dayframe-source.zip`, `Dayframe-v1.3-code-only.zip`, `README.txt`, and `apply-v1.3.sh`) is written directly inside the connected folder `/Users/shahzi/Documents/Projects/Dayframe Versions/v1.2 (2026-10-13)/v1.3 (2026-10-13)/` so the owner can move it up one level to `~/Documents/Projects/Dayframe Versions/v1.3 (2026-10-13)/` and run `apply-v1.3.sh` to sync and rebuild `~/Documents/Projects/Dayframe` in one command.
2. **Live Xcode GUI Test-Host Run (`Unverified in Sandbox`):**
   - Full `xcodebuild test` (`./check.sh --app`) requires launching `Dayframe.app` as the macOS GUI test host and rebuilding `Web/node_modules`, which live outside the connected archive folder.
   - **Mitigation:** All modified Swift files were verified with `xcrun swift-format` (0 warnings), all Python changes were verified with the 104-test `unittest` suite (`OK`), and `apply-v1.3.sh` runs `./check.sh --app` and `./build-and-install.sh` on the live repo.
3. **Grok CLI Vision Support (`Blocked on User Login`):**
   - Remains gated on `~/.grok/bin/grok login` (`.scratch/grok/issues/05-grok-images.md`).
