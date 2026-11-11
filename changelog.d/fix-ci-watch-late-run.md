- **ci-watch: a mergeable PR whose CI run starts late is a wait, and the missing-run verdict no longer blames a conflict it did not read** (test: T1) (level: reader; higher: writer — the writer of the run is GitHub, outside the repo, so only the reader can tell late from never; debt: the grace is a fixed 600 s, `CI_WATCH_REQUIRE_GRACE`)
  Measured 2026-11-10 on agent-brain #478: the PR was opened 15:24:37 UTC, `CI` and `text-leaks` started 15:28:48
  (actions/runs). The watch gave up after three reads with `CI-WATCH UNKNOWN … GitHub starts none for a PR that
  conflicts with its base`, while `mergeable` read MERGEABLE — a real conflict is caught by the two-read check before
  this branch. Now the branch reads `mergeable`: MERGEABLE waits up to the grace before counting reads; the verdict
  names the mergeable state and the possible causes. Fixture: `scripts/ci-watch-test.sh` (late start within the grace
  = GREEN; never = UNKNOWN naming `mergeable: MERGEABLE`).
