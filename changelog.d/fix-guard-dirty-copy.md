- **shared-working-copy-guard: no HEAD move over uncommitted work, also with one session** (test: T1) (level: writer;
  higher: design — a per-session record of which changes are whose would tell the operator's from the session's own;
  not needed, any uncommitted change outside the scratchpad is someone's work; debt: the session's own uncommitted
  edits are held too, commit them by path first). Measured on the macOS instance 2026-11-03: `git switch -c` ran in the
  operator's project checkout over their uncommitted settings and profiles; core rule #12 puts branch work into a
  scratchpad worktree always, the guard held only while a second session ran. Outside the scratchpad a call that moves
  HEAD or clears the tree (switch, checkout of a branch, stash, reset --hard) is held while `git status --porcelain`
  shows any change; the marker opens it. Fixture +7 (three red on the old guard).
