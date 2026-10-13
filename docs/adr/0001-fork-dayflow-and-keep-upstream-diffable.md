# Fork Dayflow and keep it comparable with upstream

Dayframe is a fork of Dayflow v2.6.0 (MIT), imported untouched as commit `1df9be4`. Forking was chosen over decompiling a closed app or building from scratch. The Swift module stays `Dayflow`, Dayflow's own files keep their style even where swift-format warns (`check.sh` only forbids new warnings), and Dayframe's additions live in their own files where possible. That way `git diff 1df9be4` stays readable and later upstream fixes can still be ported.
