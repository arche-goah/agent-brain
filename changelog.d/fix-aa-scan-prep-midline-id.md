- **brain-scan-prep: the return channel finds an order entry's `id:` inside the entry line, not only on a line of its own** (test: T1) (level: reader; higher: writer — the order-list convention allows both forms, so the reader has to take both; debt: none)
  Measured 2026-11-10 on the Windows instance (audit-audit): all 232 ids of its order list stand mid-line
  (`... | id: x | class: todo`), none at a line start; the reader matched `^\s*id:` only, so the return
  channel reported 36 of 56 findings of the last scan as "vanished". Same data with the fix: 0 vanished,
  9 still-open, 27 done-unproven (ticked without a `check:`), 16 dropped, 4 done. A word ending in `id:`
  is no id. Fixture: `scripts/brain-scan-prep-test.py` (three new cases).
