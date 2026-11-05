- **mcp-table-check reads the user layer's enabledPlugins and declared built-in servers** (test: T1)
  (level: reader; higher: design - one reader of "which plugins are on" shared by every core script; not built here,
  the scripts that read enabledPlugins have no common module; debt: none new). Measured 2026-11-05 on the Windows
  instance: the check reported "row without server: claude-in-chrome, grandma3" at every session start.
  `grandma3-next` is enabled in `~/.claude/settings.json` only, and `plugin_servers()` read the project's
  `settings.json` and `settings.local.json`; `claude-in-chrome` is brought by Claude Code itself, no `.mcp.json` and
  no plugin names it. The check now reads enabledPlugins user first, then project and local (a later layer wins, so
  a project `false` still switches a user-enabled plugin off), and takes `"builtin_servers": [...]` from the
  instance's `.claude/rules/mcp-table.json`. The fixture runs on an empty user dir (`CLAUDE_CONFIG_DIR`) so the real
  `~/.claude` never leaks in; four new cases, both directions; against main's script two of them fail.
