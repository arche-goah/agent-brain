- **A ledger entry whose check turned green is listed as "tick it", not as open work, and the pin move re-measures**
  (test: T1) (level: reader; higher: writer - ticking the box itself at the pin move would write into the instance's
  ledger, which stays the instance's own move; debt: the instance still ticks by hand, the start report names how
  many). Measured in an audit of the audits on one brain (2026-11-02): entries whose work shipped in a new pin stayed
  listed as the agent's open work for up to 17 sessions. `ledger-reconcile.py` already classified them DONE-OPEN, but
  only in its prose brief. Now (a) a registered run also writes `.claude-state/ledger-reconcile.json` (`at` + the
  DONE-OPEN rows with ledger, entry line and id); (b) `open-items.py` lists such an entry once as "check green - tick
  it" with its own count, only while that result is newer than the ledger file; (c) `brain-update.sh` runs a fresh
  reconcile after the pin moved (step 4e, bounded by the brain's `budget_s`) and prints the count. Fixtures:
  `ledger-reconcile-test.py` (result file, UNPROVEN not written), `test-open-items.sh` (fresh result ticks, an older
  one counts nothing; the old `open-items.py` fails the tick case), `brain-update-test.sh` (pin move names the count,
  no line without registered ledgers).
