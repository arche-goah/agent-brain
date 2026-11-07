- **ledger-reconcile runs `gh pr view` and `git -C <dir> ...` checks** (test: `scripts/ledger-reconcile-test.py`,
  six new cases: three refused - `--web`/`-w`, `git -C core push`, `git -C core -c ... log` - and three allowed)
  (level: reader; higher: design - a per-command option table, not built: one acting option of one new command is
  refused by name, the shell grammar stays closed; debt: an instance's own `allowed` list still replaces the
  default, so a brain that widened it locally keeps its copy until it drops the field). The default list refused the
  natural check of an entry that waits on a merge (`gh pr view <n> --json state --jq .state | grep -q MERGED`) and
  every check of the core submodule (`git -C core merge-base --is-ancestor ...`). Measured 2026-11-07 on the
  Windows instance: 10 `gh pr view` checks in its ledgers, all refused; that brain had widened `allowed` locally the
  same day, which the operator asked to weigh against a core change (translated: "always reflect whether local deviations
  are really justified, or whether the core should in fact be changed").
