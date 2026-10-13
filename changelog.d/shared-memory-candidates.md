- **A request several parties can take says who is asked first, and anyone can claim it.** (test: T1) `priority:` is an ordered list of any audience tokens on a request (a Windows check, a review, …), with an optional default per category in `parties.json`. It is information, not a sequence: there are no timers and no escalation.
  - The party asked first sees an open request.
  - Every other party reached sees it as a hint: "optional: priority n, asked first <who>; unclaimed - take it if you can and want".
  - A request to everyone without a priority is now a hint for everyone; before, it reached nobody's list.
  - `claims: <stem>` (or `answers:`) records who took it and closes it for all.

  Operator order 2026-10-13. Fixture `shared-memory-audience-test.py`, eight new cases: asked first open · asked later optional with the name before · own priority beats the default · request to everyone reaches all as optional · ranked request to everyone · a claim closes it for all · no priority means no change (control) · open-items reads the hint as a wait, not a duty.
