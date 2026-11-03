- **MCP table check: a plugin server declared inline in plugin.json counts** (test: T1) (level: reader; higher: none — the
  plugin format allows both places, the reader knew one; debt: none). Measured on the macOS instance 2026-11-03: two
  suites moved to `-next` plugins declare their server under `mcpServers` in `.claude-plugin/plugin.json`, and the session
  start reported their table rows as "row without server".
  - `scripts/mcp-table-check.py` reads `mcpServers` from the cached plugin's `.claude-plugin/plugin.json` too (an object
    only; a path string declares nothing here). Fixture +2.
