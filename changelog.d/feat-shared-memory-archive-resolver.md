- **shared-memory: settled messages move to `<area>/archive/<yyyy-mm>/` with a resolver every reader follows; one index line per month** (test: T1; settles-debt: feat-shared-memory-index-state)
  (level: design; higher: none - the convention, its mover and the readers that follow a moved file are one
  mechanism; debt: the move itself in the shared repo is a step each side runs (`shared-memory-archive.py --write`),
  not yet scheduled, and the `--days` floor (14) is the agreed figure, not a measured one).
  Agreed by both sides 2026-11-04 (shared memory core/reply-shared-memory-tidy-up… point 3b: "yes, on one condition:
  the tools still find a moved file by its file name - 66 ledger pointers in this brain name shared-memory entry paths,
  a move without a resolver breaks each of them; the archive step runs only after the resolver is in"). Resolver:
  `shared-memory-index.py` reads `<area>/archive/<yyyy-mm>/<slug>.md` as entries (`archived: yyyy-mm`), so their
  `answers:`/`closes:` keep settling, `related`/`supersedes` to a moved file keep resolving, and the topic index lists
  the month's archived messages as one line (`n archived in archive/yyyy-mm/`) instead of one per entry;
  `shared-memory-lint.py resolve_target` and `shared_answers.py` look under `archive/*/` as well; `known_targets` did
  already. Mover: `scripts/shared-memory-archive.py` (dry run by default; `--write` = `git mv` + index regeneration)
  moves only MESSAGES (request/reply/note/claim) that are settled and older than `--days`, never a durable entry,
  never an open one. Fixtures: `shared-memory-archive-test.py` (dry run moves nothing; write moves the settled old
  message and leaves the open, the young and the durable; a rerun moves nothing; the moved reply still settles its
  request; the index names the month as one line; a `related` to the moved file resolves to its new path; the lint's
  `resolve_target` finds the moved stem), `shared-memory-index-test.py` unchanged and green.
