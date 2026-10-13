# Turn on a Focus when the day starts
Status: ready-for-agent
Type: task

macOS has no public API to set a Focus, so Start of day runs a Shortcut the user picks (default name "Work Focus", using the Set Focus action) through `/usr/bin/shortcuts run`. In Settings › Start of day: a picker of the user's shortcuts, plus a button that opens Shortcuts to make one. The result is logged. Making the shortcut once is a step for the user.
