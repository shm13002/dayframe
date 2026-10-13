# Data stays in Dayflow's folder, shared with Briefing

Dayframe keeps using `~/Library/Application Support/Dayflow` (recordings, `chunks.sqlite`, timeline). Briefing (`~/Briefing`, a Python service on 127.0.0.1:8765) reads the same database. Moving the folder would break Briefing and lose history. As a consequence, Homebrew's Dayflow.app must never run at the same time as Dayframe.
