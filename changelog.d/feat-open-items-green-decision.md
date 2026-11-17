- **An operator decision whose check is green from its first run goes to the agent, not to the operator**
  (test: `scripts/test-open-items.sh` - three new cases incl. the way back, a control without a reconcile result stays human;
  negative control: the pinned open-items.py fails the new case)
  (level: reader; higher: writer - the session that applies an operator answer ticks the entry in the same turn,
  not built because no tool sees the moment an answer is applied; debt: a decision entry with `check: none`
  or a stale check stays human - two of the four measured cases). Measured 2026-11-17 on the macOS instance:
  four entries the start report gave the operator as "needs you" were settled - two by the operator's answer the
  day before, one by a decision the agent was allowed to take, one by a word in a data file. ledger-reconcile
  had named two of them "green from its first run - negative control missing", in prose only.
  `ledger-reconcile.py` now writes those positions into `.claude-state/ledger-reconcile.json` (`unproven`, next
  to `done_open`); `open-items.py` moves a `human` ledger item found there to `ai`, with the note "read the
  record: the answer may be in, tick it with the evidence". The way back (Windows review 2026-11-17): an entry that carries `record-read: <date> …` - the agent read the record and the answer is not in it - stays the operator's, marked "its check is weak", so a weak check never keeps a real decision away from the operator. The freshness rule of
  `done_open` holds: a result older than the ledger file counts nothing.
