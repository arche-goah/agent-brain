- **local-machinery: a same-named file is a shadow only when it is a copy of the core file** (test: T1) (level: reader;
  higher: writer - a declaration could name `distinct_from` for a core file too; not built, the file text already
  says it; debt: a copy that drifted below half of the core file's lines is read as another tool - it still surfaces
  as an undeclared or declared instance item, never silently). Measured 2026-11-02 and 2026-11-03 on two Windows
  instances: the session start said at every boot "1 instance item(s) shadow a core item of the same name:
  scripts/telegram-notify/notify.cjs - use the core one and remove the copy"; that file is the operator's messaging
  hook and shares 13 % of its lines with the core's sound `helpers/notify.cjs`. Same finding class as the duplicate
  check of `hook-coverage.py` (agent-brain#316, same reading: a copy keeps at least half of the lines). `judge()` now
  calls a same-named script, skill or workflow a shadow only when it calls the core one (wrapper) or `copy_of()` holds.
  Replay on the reporting brain: `shadow=1` before, `shadow=0` after. Fixture `test-local-machinery.sh` +2 (the
  other-tool case red against main, a drifted copy keeping 3 of 4 lines still a shadow).
