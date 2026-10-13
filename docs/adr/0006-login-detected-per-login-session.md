# The login welcome is keyed to the macOS login session, not to how the app launched

At login, both the login item and the keep-alive agent (`open -g`) can start Dayframe, and either may win. Launch type ("launched as login item") is therefore unreliable. The first-launch cue plays when the login session's `CGSSessionUniqueSessionUUID` differs from the last one welcomed and the session is under 4 minutes old (measured by the Dock's process start time). It plays at most once per login session, and a relaunch later in the same session never plays it.
