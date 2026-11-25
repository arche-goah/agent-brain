- **The background ledger reconcile opens no terminal windows on Windows any more** (test: T1)
  (level: writer; higher: design — a shared "start a background run" helper for every script;
  only one Python site launches detached today, a helper for one caller is not worth it; debt: none).
  `ledger-reconcile.py --cached` started its background run with `DETACHED_PROCESS`, so the run had
  no console and every console child without a hand-set flag got a new one. #41 flagged the per-check
  `bash` only; the `gh pr view` and `git` calls stayed unflagged, and every session start opened
  3 Windows Terminal windows that took the operator's focus (measured 2026-11-25 on a Windows brain
  with a window watcher, EnumWindows every 50 ms: the hidden `--cached` call alone 3 windows; with
  the launch on `CREATE_NO_WINDOW` 0, the background run still wrote its stamp). The launch now uses
  `CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP`: the run owns a windowless console and every child
  inherits it, so a child added later cannot reopen the class. OS-18 in `docs/os-traps.md` records
  the repeat.
