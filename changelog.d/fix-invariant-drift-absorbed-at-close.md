- **session close: the invariant register's drift is read and absorbed every close, never piled up**
  (test: T1) (level: writer; higher: design — an instance register could exclude the pinned core's own fixture
  files from its class searches, so a pin brings no drift at all; not built: which instance class may skip core
  files is a judgement per class; debt: a real new site is now absorbed after one session, so its only trace is
  the close output and the session-log count) — measured 2026-11-16 on the macOS instance: the register drifted
  for the third brain-scan in a row, 174 drift lines today (the scan counted 294 with its headers), 119 of them
  (68 %) new fixture files of the pinned core that match an instance class; nobody pulled the baseline between
  scans. The operator decided the same day (question tool: close it mechanically). `scripts/invariant-check.py
  --write` reports as before, then rewrites the drifted `known:` lines to today's counts (keeping the
  one-line or one-file-per-line form, every other line byte-identical) and exits 0 unless a search could not
  run. `helpers/session-closing.sh --pre-commit` runs it on `docs/maintenance/invariants.md` when present,
  prints the drift lines it absorbed, and names the count in the close line. Fixtures:
  `scripts/invariant-check-test.py` 2c (+3: reports then absorbs with rc 0, only the drifted line changes, a
  plain run is quiet after) and `scripts/test-session-closing.sh` (+5: names the drift, says it absorbed it, the
  baseline holds today's count, the close line names it, no line without drift); against main all 8 fail.
