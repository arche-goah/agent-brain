- **A run that ends BLOCKED keeps its away-channel** (test: T1) (level: writer; higher: none — the run itself knows it is
  blocked and says it; debt: none). Coherence register 2026-11-02 P1-13 (fifth round after KS-110, PLAUSIBLE): the BLOCKED
  end of an autonomous run said "report through the instance's channel for an absent operator, then disarm" — but `disarm`
  removed the state the watchdog's issue alarm (operator decision 2026-10-15: GitHub mail) would have fired on, and nothing
  sent the report. `scripts/loop-watchdog.sh disarm --blocked "<reason>"` logs the reason and opens the issue with it, then
  ends the run; a plain `disarm` opens none. `skills/autonomous-run/SKILL.md` hard gate 6 names the call. Fixture +3.
