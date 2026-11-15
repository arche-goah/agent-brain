- **open-items-gate: the first reply counts the session start's own findings and says what happened to each**
  (test: T1) (level: reader; higher: writer — session-bootup could give every `!!` line a stable id and a
  per-finding counter ("reported in N sessions, nothing done"), so a finding said "handled" but back at the next start
  gets louder; not built in this step: it touches every check that prints a `!!` line; debt: the gate reads words, a
  reply that says "handled" without the act passes until that counter exists) — measured 2026-11-11 on the macOS
  instance over 60 transcripts: top-level `!!` lines of the session start (red self-tests, ledger checks, template
  permission drift, an auto-fire gap, a done deadline) stood in 13 to 30 session starts unfixed. The first reply only
  had to report them, nobody owned them, and almost every session is a topic session that stays on its topic. The
  operator decided the same day (question tool): every session, first turn. `bootFindings()` takes every top-level
  `!!` line outside the open-items block; the first reply must say "<n> session-start findings" (the noun is part of
  the count: a bare number matched by chance) and a handled word (handled now, handed to the owner, or the blocker);
  an instance adds its language as `finding_unit_patterns`. Replay over the same 60 transcripts cut at the first
  turn's stop: 45 first turns judged, all with findings, 42 now blocked on them (3 blocked earlier for another
  reason). Fixture: `scripts/test-open-items-gate.sh` case 26 (+5: counted and handled passes, only reported blocks,
  handled but not counted blocks, a matching number without the noun blocks, an indented sub-line alone asks nothing).
