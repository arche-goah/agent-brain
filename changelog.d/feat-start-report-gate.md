- **start-report-gate: no outward call in a session's first turn before the start report, unless the first message orders work — ported from an instance alpha** (test: T1) (level: writer; higher: design — open-items-gate checks the CONTENT of the first reply after the fact, this holds the effect before it; one carrier for both would need the Stop and the PreToolUse event in one file; debt: the order words are data, English in the template, other languages per instance)
  Incident 2026-10-27 (the macOS instance): the operator asked "status?", the session start listed a PR under a
  standing approval, the AI merged it before any reply. Evaluated 2026-11-10 over 168 sessions: 1 real catch, 5
  false alarms in 2 sessions (both causes fixed in the alpha: a question-tool answer opens a turn, a message typed
  mid-turn is an order), no operator turn spent; ported on the operator's decision the same day. `--replay` now
  ends the first turn on a question-tool answer too (8 of 10 replay hits of the evaluation were such turns).
  Data `templates/rules-instance/start-report-patterns.json`. Fixture: `scripts/test-start-report-gate.sh` (20).
  Windows review: the first turn ends where the harness closed it (`system/turn_duration`), not at the second prompt -
  a session opened on one prompt and then driven by notifications stayed in its first turn for hours (18 outward calls
  over 2 h 24 min in one replayed session). PowerShell is judged like Bash; the escape's quote must stand in the
  operator's own words; `please` alone is no order word in the template; `--replay` without a pattern file says so
  and exits 0. Fixture +10, the five findings red on the old head.
