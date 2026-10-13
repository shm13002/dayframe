# "Today's apps" row on Briefing
Status: ready-for-agent
Type: task

Briefing shows the day apps as a row of icons. Click one to open or bring it forward; "Set up my day" runs Start of day. React page: data comes through `setContext`, clicks come back through the `dayframe` message handler. The native fallback Briefing gets the same row.
