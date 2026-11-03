- **turn-kind: one reader for a prompt the operator typed, `operatorPrompt()`; basics-hint and the stop dispatcher's
  turn kind use it** (test: T1) (level: reader; higher: design - a lint that flags every `role === 'user'` outside
  turn-kind, not built because the measurement found 12 of the 14 such readers use user records only as a turn
  boundary, where a lint would be noise; debt: none). A prompt typed while the agent works lands as a queued command
  (`attachment.queued_command`, origin human), never as a user record. Measured on the macOS instance 2026-11-03 over
  the 14 helpers that read user records without `queuedHumanPrompt`: 12 use them only as a turn boundary (a missed
  queued prompt widens the window, no operator word is lost); two read the operator's text and missed every
  typed-ahead prompt: `basics-hint.cjs` (a close typed ahead was not learned, so the hint came back) and
  `stop-dispatcher.cjs` `turnKind` (a turn opened by a notification and then answered by the operator stayed a
  notification turn, so checks with `onNotification: skip` sat it out). Agreed with the operator on 2026-11-03
  (question tool). Fixtures: `test-turn-kind.sh` +2, `test-stop-dispatcher.sh` +2, `test-basics-hint.sh` +1; the
  dispatcher and basics-hint cases FAIL against main.
