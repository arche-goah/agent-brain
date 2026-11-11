- **open-items-gate: a date alone is no mention of an open item** (test: `scripts/test-open-items-gate.sh` +2, the new allow case red against the v2.1.4 gate) (level: reader; higher: writer - give every item an id the reply must quote, not done: replies name requests by date and topic in prose, an id would be a second vocabulary; debt: none)
  Measured on the Windows instance 2026-11-11: a BLOCKED line carrying a ledger id `…-2026-11-11` was read as
  "puts request-content-review-…-2026-11-11 with someone else" — the relabel check's `strict()` took any line holding
  an open item's date as a mention of it. The date now counts only together with one of the item's own topic words
  (`topicWords`, generic words left out) in the same line; `#n` and the exact file stem stay as they were.
