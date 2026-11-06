- **Two core guard rows ported from an instance: a git path list as an unquoted shell variable, and `git stash`
  in any worktree** (test: `scripts/test-guards.sh`, eight cases) (level: writer; higher: design - not taken, the
  shells' word splitting and the shared stash are facts of the tools, not of the core; debt: a stash a session
  really needs (none known) now needs the marker). Both rows ran as instance data on the macOS instance since
  2026-11-02 and were declared general there on 2026-11-06 (local-machinery: no identity token). Variable path
  list: `git add $F` / `git commit -- ${FILES}` - zsh passes the value as ONE path ("pathspec ... did not match",
  measured twice on 2026-11-02), bash splits it, PowerShell does neither; written-out paths and a `$5` in a message
  pass. Stash: the stash lives in the repository that every worktree shares; a stash for a negative control emptied
  a worktree's changes and the control ran against the wrong test (2026-11-02). `shared-working-copy-guard.cjs`
  blocks stash only while a second session shares the checkout; this row covers the single-session worktree case.
  `git stash list` / `git stash show` only read and pass.
