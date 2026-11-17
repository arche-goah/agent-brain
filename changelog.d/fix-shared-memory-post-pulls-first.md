- **shared-memory-post pulls before it writes; behind with local changes it writes nothing** (test:
  `scripts/shared-memory-post-test.py`, 2 new cases - behind and clean: pulls, then writes; behind with an
  uncommitted change: refused, no file touched; both fail against the script on main, which writes onto the stale tree)
  (level: writer; higher: design - a post that commits and pushes itself in one step would leave no window at
  all, not built because the by-path commit stays the caller's (working rule #12) and a push is outward; debt: offline (fetch
  fails) it still posts on the local state, said on stderr, and the pre-commit check guards the commit as before).
  Measured 2026-11-16 on the macOS instance: the checkout was one commit behind (another instance had pushed), the
  script wrote the request and regenerated `INDEX.md`, `core/INDEX.md`, `core/OPEN.md`; the pre-commit hook refused
  the commit as behind, `pull --ff-only` refused over the regenerated pages, and the two ways left - discarding the
  post or committing past the hook - were both refused by the permission layer; the operator had to release the
  commit. The script's own docstring already said a request is written "after a pull"; nothing made it so. Now
  `pull_first()` fetches, fast-forwards a clean behind checkout and refuses a dirty one before the first write.
  The `--ff-only failed` refusal (a diverged checkout) now names the same way out as the dirty one, `git pull --rebase`
  with an own commit (fixture case "behind and diverged"; Windows review 2026-11-17).
