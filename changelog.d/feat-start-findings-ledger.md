- **start-findings: the session start's own findings become tracked entries with an id, an owner and a counter; the
  first reply names only what needs the operator and what keeps coming back** (test: T1) (level: writer; higher:
  design — each check could own its finding and its fix state, not only print a line; not built: it touches every
  check that prints `!!`, and the id is enough to count and escalate; debt: a line whose list ends in prose
  (`…: one-item - name the command`) is not read as a list and gets a new id when its item changes; the owner is a
  pattern on the line's own words, and "handled" is a command, not read from the reply) — operator order 2026-11-12
  (translated, question tool "Yes, like this"): the findings move to the writer level so the operator is not flooded
  and nothing is lost; one count line plus at most three operator items; a finding that keeps coming back goes loudly
  to the operator after n sessions. `scripts/start-findings.py record` (called by `session-bootup.sh` before the
  32 KiB cut) gives every top-level `!!` line outside the open-items block a stable id (8 hex of the line with dates,
  shas and numbers normalised; a line whose part after its last ": " is a list — "," or " | ", or one item without a
  space — is keyed by its head, the list kept in the stored text), owner `ai` or `operator` (built-in "ask the
  operator" patterns, the instance's `operator_patterns` in `.claude/rules/start-findings.json`), first/last seen,
  `sessions_seen` (information) and `days_seen` (distinct local dates) in `.claude-state/start-findings.json`; a
  finding no longer printed is closed, one marked `handled <id> --how` that is back at a later start is reopened with
  the mark cleared. Loud counts days, not sessions (`loud_after_days`, default 3): several sessions start on one day,
  and a session counter made 17 items a start loud in the replay. The start prints a count line, up to three operator
  items and every loud one in place of the lines; a hand run (no session id) and `BOOTUP_FULL_FINDINGS=1` keep every
  line, `list` prints them all with their sub-lines, the proof lines session-audit reads stay verbatim.
  `open-items-gate.cjs`: with the brief view the first reply carries "<n> session-start findings", a handled word, and
  names each operator or loud item by its id or two of its own words; without it #502's rule holds unchanged;
  `mandatedTopics()` reads the operator item through its tag. Replay over the last 30 session starts of the macOS
  instance's transcripts (2026-11-08 to 2026-11-12, five local days, 8 to 18 findings each, 381 lines): 81 distinct
  raw lines fold to 36 ids (45 before the list-head rule; `PR waiting on you` alone had 25 variants), 24 of them back
  in 5 or more starts. Simulated over the same starts with nothing handled: loud 0 to 10 a start (last 5, none before
  the third day), 163 items to name in the first replies instead of 381 lines (243 with the session counter).
  Fixtures: `scripts/start-findings-test.py` (36 cases: id across a changed count/date/sha, list tails keep the id,
  different heads and prose tails do not, one count per session and per day, loud after N days, closed and reopened,
  handled held in its session and cleared at a later start, operator cap of three, hand run unchanged and unwritten)
  and `scripts/test-open-items-gate.sh` case 27 (+7: count line and operator item passes, operator item left out,
  count left out, loud item left out blocks, loud item by id passes, the brief's own line count without the operator
  item blocks, mandated topic through the tag). Negative controls: case 27 against the gate of main — 4 red (two
  allow cases blocked, the unnamed operator item let through, the mandated topic read as `[finding|operator] <id>
  update available`); the list and day cases against the session-counting first version of the script — the two
  list cases red, the day cases stop on the missing `days_seen`; all green after; #502's case 26 green throughout.
