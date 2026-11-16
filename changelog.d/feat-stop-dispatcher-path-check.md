- **stop-dispatcher: a check row runs only a script under the project's core/helpers/, scripts/ or .claude/**
  (test: T1) (level: writer; higher: design — a signed or hashed list of check scripts would also catch a
  changed file inside an allowed folder; not built: the allowed folders are already the brain's own tracked
  files, guarded by the commit path; debt: a file placed inside an allowed folder still runs) — a Windows
  instance's coherence scan (2026-11-16) found that `run()` resolved `check.cmd` without a path check and ran it
  with node at every turn end: whoever could write `stop-checks.json` or a file it names ran code. The operator
  agreed the same day. After resolving, the path must lie under the project's `core/helpers/`, `scripts/` or
  `.claude/`, or under this dispatcher's own core (`helpers/`, `scripts/` — the plugin copy of the same
  helpers); `..` cannot climb out (compared after normalising, case-insensitive on Windows). Otherwise one line
  "check path outside the allowed folders" and the check does not run. The fixture's probes moved into each test
  project's `.claude/probes/`. Fixture: `scripts/test-stop-dispatcher.sh` (+4: a temp-folder script does not run,
  the refusal is named, a `..` path cannot climb out, a script under `scripts/` runs); three of them fail on main.
