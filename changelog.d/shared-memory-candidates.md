- **A category request can rank who takes it.** (test: T1) A request to `os:windows` (or any category) reached every party equally: nobody could tell who was expected, and a party with little quota read a broadcast as a duty. New, per task: `candidates:` (an ordered list of any audience tokens) and `escalate_after:` (hours per rank), with a default order per category in `parties.json`.
  - The first candidate sees an open request.
  - A later candidate sees it at session start as waiting: "queued: candidate n, after <who>, unclaimed; yours from <time>". It turns into an open request only once nobody before them took it in time.
  - `claims: <stem>` (or `answers:`) closes it for everyone.
  - Without a ranking, nothing changes.

  Operator order 2026-10-13 ("not always A-B-C — generic ways to rank and to code tasks"). Fixture `shared-memory-audience-test.py`, seven new cases: first candidate open · later candidate queued with the name before it · past the escalation time it is theirs · the entry's own order beats the default · a claim closes it for all · no candidates means no queue (control) · open-items reads a queued line as a wait.
