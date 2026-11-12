- **Core guard rows: a core gate run through a pipe, and `claude plugin update` without a marketplace refresh**
  (test: `scripts/test-guards.sh`, eight cases: four block, four controls) (level: writer; higher: design - not
  taken, a gate cannot stop a caller from piping it; debt: the gate name list is the one measured on the Windows
  instance, a new gate joins it by hand). Both ran as instance rule data on the Windows instance since 2026-08-04
  (a red gate slipped through `| tail` into a commit and a push; a stale marketplace clone wrote an older version
  back); the instance's local-machinery check classed them as general on 2026-11-07, so they move to the core
  (Working Rule #11, port of running instance machinery). A gate with its exit code read on its own, reading a
  gate script through `git show ... | sed`, an update after `claude plugin marketplace update` in the same
  command, and the phrase quoted in a commit message pass.
