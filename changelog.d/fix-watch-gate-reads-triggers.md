- **watch-gate reads a workflow's `on:` before it calls a push a CI run** (test: `scripts/test-watch-gate.sh`, 8 new
  cases - a feature-branch push into a repo whose workflow runs on `push: branches: [main]` and `pull_request` is no
  run, also in the list form and for a tags-only workflow; a push to main, `HEAD:refs/heads/main`, a `release/**`
  branch, a bare push and `on: [push, ...]` stay runs; the three "no run" cases fail against the gate on main)
  (level: reader; higher: writer - asking GitHub whether a run started would be exact but costs an API call at every
  turn end and arrives late, not built; debt: a line reader for the common `on:` forms - an unusual form counts as a
  run, the side the gate already errs to). Measured 2026-11-16 on the macOS instance: four suite branches pushed,
  the Stop check demanded a watcher for each; `gh run list --workflow CI --branch <branch>` showed zero runs in all
  four - their CI runs on main, tags and pull requests only. `ciStarted()` took "the checkout has a workflow file" for
  "this push starts a run". Replayed through the gate with those four repos' real workflows: the gate on main blocks
  all eight pushes (branch and main), this one blocks the four main pushes and none of the branch pushes.
