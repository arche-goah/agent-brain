- **autonomous-idle-gate: a release the operator left for a new topic no longer holds the interactive turn** (test: T1) (level: reader; higher: writer — the release could carry an end the operator states, but nobody states one, so the reader has to see the topic change; debt: "a new topic" is any typed own message of 12+ characters (the ` (recommended)` suffix cut) that names neither the entry id nor the release words and is no bare continuation — a side question ends the release too, on the allow side, decided so)
  Measured 2026-11-10 (evaluation of the interactive alpha on the macOS instance, operator decision the same day:
  keep it, with this fix): 36 interactive blocks in 1643 interactive turns, 28 of them in ONE session, every one on
  a release given at 18:01 that the operator then left for other topics for five hours. A release now ends with
  the operator's next own message that names neither the id nor the release words; a short reply does not end it.
  Fixture: `scripts/test-autonomous-idle-gate.sh` (four new cases: new topic, short reply, message naming the
  entry, earlier topic before the release).
  Windows review (79 of 80 operator messages on one machine were 12+ characters, 36 of them question-tool answers
  carrying ` (recommended)`): a question-tool answer never ends a release, the suffix is cut before the length, and a
  bare continuation ("please continue"; other languages as `continue_patterns`, template documented) is no new topic.
  Fixture +4, three red on the old head; a typed new topic after an answer still ends it.
