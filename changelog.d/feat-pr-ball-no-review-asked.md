- **pr-ball names an own core PR whose review was never asked for**
  (test: `scripts/test-pr-ball.sh` cases 16-17 - six new cases, negative control: the pinned pr-ball.py is
  silent on the measured case, the new one names it)
  (level: writer; higher: design - a PR opener that posts the request itself, not built here because the
  request's addressee and wording are the author's judgment; debt: a PR-shaped number in an own text meant for
  another PR still silences the line - rare, since a number counts only where it is PR-shaped and in the review
  repo's own topic folder). Measured 2026-11-17 on the macOS instance: eight own core PRs sat
  about five hours as "standing" items with the content review they need noted only as a session-log `open end:`
  line; no request stood in the shared memory, and no check said so. `pr-ball.py` now prints
  `yours - no review asked` for an own open PR in a review repo (`agent-brain`, or the comma list in
  `PR_BALL_ASK_REPOS`) that is an hour or more old, has no word from anyone else, and whose number no own
  shared-memory fact file in the repo's topic folder (`core/`, `PR_BALL_ASK_AREA`) names PR-shaped - `#N`,
  `PR N`, `core N`, `core N-M`, or `core-N-M` in the file name (`shared_answers.own_named_numbers`). A bare
  number does not count: the Windows review measured that a plain number match covered 61 % of 400-700 on one
  device and silenced 4 of the next 30 core PRs. The bootup query asks `createdAt`. Replay over the live PR
  list against the shared memory before the request: exactly the eight PRs, no other, and none of 571-600
  silenced.
