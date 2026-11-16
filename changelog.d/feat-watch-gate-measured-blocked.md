- **watch-gate: a measured BLOCKED end with a declared watcher gap passes**
  (test: T1) (level: writer; higher: design — the session start could carry a machine's watcher capability
  as state (can poll / cannot), so no reply has to name it; not built: one declared key per gap is enough
  for the case measured; debt: the gate trusts that the declared entry still fits the machine) — a Windows
  instance's coherence scan (2026-11-16) measured that the gate had no BLOCKED case: a machine that cannot
  keep a watcher alive (a show machine offline, a channel it may not poll) was held at every turn end
  although the gap was written down. The operator agreed the same day. A reply with a `BLOCKED:` line AND
  `WATCH-GAP: <key>`, the key an entry of `.claude/rules/local-machinery.json` (instance / external / alpha),
  passes the watcher findings a close could also cover ((a), (b), (d), (f), (g)); a hand step or reload asked
  of the human and a done claim over an unread CI verdict are never covered. Fixture:
  `scripts/test-watch-gate.sh` (+4: declared gap passes, undeclared key blocks, no BLOCKED line blocks, a hand
  step still blocks); the passing case fails on main.
