# Grok CLI and Grok Bot can read Dayframe (MCP)
Status: done
Type: task

Add Grok to the MCP / CLI tab's agent clients, writing Dayframe's MCP server into `~/.grok/config.toml`. Find out whether Grok Bot.app takes MCP servers, and where. If it does, register it too; if not, say so in the UI and in this ticket.

## Comments

- 2026-10-13 13:47: Grok CLI done (CHANGELOG 13:47). Grok Bot: not possible today. It has no local MCP config, and its only MCP link is grokbot://mcp/oauth/callback, which is for remote servers; Dayframe's server is local stdio. Revisit if Grok Bot gains local MCP servers.
