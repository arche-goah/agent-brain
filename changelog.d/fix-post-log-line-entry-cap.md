- **`shared-memory-post.py` refuses a LOG line over the entry cap before it writes** (test: T1) (level: writer;
  higher: design - a pre-commit lint run in the shared-memory repo, not built here because that repo has no hook or CI
  and every entry is written by this tool; debt: lines written by hand stay judged only by the lint at session start).
  Lint check 6c judges new LOG entries against the rotate tool's `ENTRY_CAP` (300 B) since 2026-10-31, and its fix
  text points at this tool - yet this tool built the line from title, recipients, path and one-machine reason with no
  size check, and nothing ran the lint before the commit. Measured on the macOS instance 2026-11-03: 17 entries over
  the cap since 2026-10-31 (two writers), every one written by this tool. The line is now built before anything is
  written; over the cap the call is refused with the byte count and what to shorten. One fixture case, red without
  the fix.
