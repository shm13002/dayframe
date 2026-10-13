# Format Dayframe's Swift to zero warnings
Status: ready-for-agent
Type: task

Run `xcrun swift-format format -i` on every Swift file Dayframe created (22 files had warnings), and fix by hand the warnings Dayframe edits added to 12 Dayflow files (leave Dayflow's own pre-existing warnings). Mechanical, so it gets its own commit. Done when `./check.sh` reports no Swift problems and the app builds and its tests pass.
