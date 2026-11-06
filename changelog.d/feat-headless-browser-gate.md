- **New PreToolUse gate `helpers/headless-browser-gate.cjs`: the AI's own browser checks never open a window on the
  operator's screen** (test: `scripts/test-headless-browser-gate.sh`, nine cases) (level: writer; higher: design - not
  taken, the core ships no browser server template, so the flag is checked where each brain keeps its config; debt: a
  plugin-provided browser server is not judged, its args are not in the brain's `.mcp.json`). Ported from the macOS
  instance, where it ran since 2026-10-28 after a Playwright check opened Chrome unasked (operator: "invisible, unless it
  is explicitly about me seeing it"; measured cause: `@playwright/mcp` and `chrome-devtools-mcp` start visible by
  default). A playwright or chrome-devtools tool call (also under a plugin prefix) is denied while that server's args lack
  `--headless`; with the flag, an undefined server, another tool, or a missing/unreadable `.mcp.json` it passes.
  Wired in `hooks/hooks.json` with its own narrow matcher.
