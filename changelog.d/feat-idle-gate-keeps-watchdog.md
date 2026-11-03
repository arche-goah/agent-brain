- **The loop watchdog follows the autonomous mode** (test: T1) (level: writer; higher: design — the mode itself as a state
  file with its own lifecycle (on, off, close) that the watchdog reads; not built, the mode is read from the transcript on
  every call and has no switch moment; debt: a turn that runs longer than the silence limit without a turn end raises the
  alarm, as intended). Coherence register 2026-11-02 P1-12 ("watchdog arming in prose only", CONFIRMED); measured on the
  macOS instance 2026-11-03: a list run ordered autonomous worked for over an hour with no watchdog armed. At every turn end
  `autonomous-idle-gate.cjs` arms `auto-autonomous-run` (45 min, `LOOP_WATCHDOG_AUTO_MINUTES`) when nothing is armed and
  beats otherwise; in interactive mode it disarms a watchdog it armed itself and leaves a hand-armed one alone. No turn is
  held for it; `LOOP_WATCHDOG_AUTO=0` switches it off. Fixture +4.
