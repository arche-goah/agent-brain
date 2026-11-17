- **suite-check: an MCP server version written into the code is a finding**
  (test: T1) (level: reader; higher: writer — a shared start helper that every suite server uses to read
  its version from plugin.json would remove the literal at the source; not built: the four servers are in
  three languages and each fix is a few lines in its suite; debt: a server that hardcodes the version in a
  form the pattern does not know stays unseen) — measured 2026-11-16 on the macOS instance: four suites wrote
  the server version into the code, three already apart from their plugin.json (0.2.0 vs 0.2.15, 1.0.0 vs
  1.0.7, 0.1.0 vs 1.0.4), so `initialize` reported a stale version. The operator agreed the check the same
  day. `server_version_findings()` WARNs per literal (`SERVER_VERSION = "x.y.z"`, `serverInfo` / `McpServer` /
  `Server(` with a `version` literal) in tracked source outside tests and fixtures, and says whether it
  already differs from plugin.json. Run over the four suites: four findings, one each. Fixture:
  `scripts/suite-check-test.py` (+4: a differing literal, an equal literal, a fixture stub is none, a version
  read from plugin.json is none); the two finding cases fail on main.
  A literal in a suite whose plugin.json has no version now says "no plugin.json version to compare" instead of
  "equal to plugin.json today" (fixture case "a literal with no plugin.json version"; Windows review 2026-11-17).
