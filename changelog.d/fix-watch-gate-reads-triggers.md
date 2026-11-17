- **watch-gate reads a workflow's `on:` before it calls a push a CI run** (test: `scripts/test-watch-gate.sh`, 14 new
  or changed cases - a NEW branch (`[new branch]` in the push output) into a repo whose workflow runs on
  `push: branches: [main]` and `pull_request` is no run, also for a tags-only workflow and for `pull_request.types`
  without `synchronize`; an update of an existing branch (a follow-up commit on an open PR), a quiet push, a push to
  main, `HEAD:refs/heads/main`, a `release/**` branch, a bare push and `on: [push, ...]` stay runs; `-o <value>`, a
  second push in one call and a column-0 comment inside `on:` are read right; the changed cases fail against the
  gate before the Windows review's finding was fixed)
  (level: reader; higher: writer - asking GitHub whether a run started would be exact but costs an API call at every
  turn end and arrives late, not built; debt: a line reader for the common `on:` forms - an unusual form counts as a
  run, the side the gate already errs to). Measured 2026-11-16 on the macOS instance: four suite branches pushed,
  the Stop check demanded a watcher for each; `gh run list --workflow CI --branch <branch>` showed zero runs in all
  four - their CI runs on main, tags and pull requests only. `ciStarted()` took "the checkout has a workflow file" for
  "this push starts a run". Windows review 2026-11-17 (finding at f311d07): the first version read the core's own
  `ci.yml` form as "no run" for EVERY branch push, so a follow-up commit on an open PR - the case working rule #9
  names - asked for no watcher. A push to an existing branch now counts as a run through `pull_request`
  (synchronize); only a push the output shows as `[new branch]` is exempt, since no PR can exist for it yet.
