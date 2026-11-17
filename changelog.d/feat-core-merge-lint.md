- **core-merge-lint: a core merge waits for the lint on the merged state, a core push for the lint at the pushed commit — ported from an instance alpha** (test: T1) (level: writer; higher: design — a merge queue would build the merged state on GitHub itself; not available to a personal account (measured `owner.type: User`); debt: the lint runs on the merging machine's OS only, the other OSes see the merged state first in the CI after the merge)
  The core ruleset does not demand "branch up to date"; what that rule caught (2026-10-27: CI green against an old
  main, red against today's) was carried on one brain by an alpha since 2026-10-28, used in 129 sessions; the push
  half since 2026-10-30, after a class of pushes linted on fixtures alone and red in the CI minutes later
  (2026-10-21 twice, 2026-10-26 three times, 2026-10-30). New: `scripts/core-merge-lint.sh <pr>` (the PR's BRANCH
  head merged with today's main in a throwaway clone, ci-lint-local plus every fixture naming a touched file; main
  already in the head = the head's CI counts), `scripts/core-push-lint.sh [--fast] <worktree>` (one run per machine,
  a lock, a commit scan with the brain's leak watch list before the long lint), `helpers/core-merge-lint-gate.cjs`
  wired as a PreToolUse Bash hook, and a `mechanism-rules.json` row that holds a full push lint outside a train head
  (2026-11-11: ten branches linted in full one by one, ~2 h queue). The core repo is data — `CORE_LINT_REPO`, else
  the origin of the core checkout — never a name in the code; a push to `<repo>-shared` no longer matches as the
  core (the alpha matched by substring). Fixtures: `scripts/test-core-merge-lint-gate.sh` (26, both directions),
  `scripts/test-guards.sh` (+5 rows).
