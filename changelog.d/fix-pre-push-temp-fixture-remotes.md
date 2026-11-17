- **pre-push leaves main free for a fixture's remote under the system temp** (test: `scripts/test-pre-push.sh`, 6 new
  cases - main of a temp bare repo passes, also as `file://`; rewrite and delete there stay blocked; main of a remote
  outside the temp roots stays blocked; the new cases fail against the hook on main)
  (level: reader; higher: design - a fixture could declare its throwaway remote, but every suite writes its own
  fixtures and none knows of this guard; debt: a real bare repo someone keeps under /tmp or $TMPDIR is free for main
  pushes now - rewrite and delete stay guarded there). Measured 2026-11-16 on the macOS instance: a suite's
  `release-preflight-test.sh` pushed main into a `mktemp -d` bare repo and was refused on the machine ("push to main
  of tmp.../repo-...-origin (not in main_ok)"), 8/9 locally while CI, which has no brain hook, was green. The hook now
  treats a remote that is a local path (plain or `file://`) resolving under `$TMPDIR`, `$TEMP`, `$TMP`, `/tmp` or
  `/var/tmp` like a listed repo for the main rule only. With the change the same suite test passes 9/9. The core's own
  fixture keeps its guarded remotes under `$HOME` so the main block is still exercised.
  A `file:///C:/...` URL now loses the slash before the drive letter and counts like `file://C:/...` (fixture case
  "the same remote as a file:/// URL passes"; Windows review 2026-11-17).
