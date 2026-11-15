- **merge-request-gate: a PR that touches only a suite's declared `data_paths` needs no OS OK**
  (test: `scripts/test-merge-request-gate.sh` +7 cases - two data PRs allow, a code file next to the data rows,
  a nested path under a one-segment glob, an unanchored suffix, an empty file list and a suite without
  `data_paths` all block; negative control: the two allow cases block against the gate on main)
  (level: writer; higher: design - a PR class field in the core's own rule data instead of a suite list, not built
  because only suites carry pure data folders today; debt: a suite has to declare its globs in its
  `dependencies.json` before the class applies there). The gate demanded a macOS and a Windows OK for every
  suite PR, also for one that only adds result rows to a release record - there is no OS behaviour to check, and
  the only way through was a `BETA-MERGE` label that was false for a data change. The gate now reads the PR's file
  list (`gh pr view --json files`) and lets it through when every file matches one of the suite's `data_paths`
  globs (anchored, `*` inside one path segment, `**` across). A PR without a readable file list is not a data
  change.
