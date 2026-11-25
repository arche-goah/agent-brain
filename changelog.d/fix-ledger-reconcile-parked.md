- **A ledger entry the operator parked is no longer reported as "done but still open"** (test: T1)
  (level: reader; higher: writer — a ledger writer that refuses a check on a parked entry; a parked entry keeps
  its check on purpose, it measures the work done so far and is reused when the operator takes it up again;
  debt: none).
  `ledger-reconcile.py` put every open entry whose check passes into DONE-OPEN, and the session start asked to
  tick it. An entry whose current `exit:` is `parked` (the operator stopped it as it is, taken up again on their
  word) is open on purpose; reporting it every start asks the AI to close what the operator chose to leave.
  Measured 2026-11-25 on a Windows brain: two parked entries stood in every start report as "check green - tick
  it" since their park on 2026-11-23. Now an entry whose `exit:` line (not a `was-exit:`) says `parked` is not
  DONE-OPEN. Fixture in `scripts/ledger-reconcile-test.py`: red against the old reader, green now.
