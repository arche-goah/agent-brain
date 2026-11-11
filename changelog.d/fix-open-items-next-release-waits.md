- **open-items: a PR a closed release scope left out for a later release is the operator's, not standing**
  (test: T1) (level: reader; higher: writer — release-scope.py could write the wait into the PR body as a
  `waiting-until` line, but the next release has no date to write; debt: PRs of a sibling instance left out of the
  same release still read as `wait` on that instance, their author) — measured 2026-11-11 on the macOS instance:
  release scope 2.1.5 closed with the tag and excluded 21 own core PRs "collected for the next train"; open-items
  printed them as `standing` ("handle these, no question") in up to 25 session starts. The only move left was
  starting the next train or release, an operator decision, so no session could act and none asked. Now
  `next_release_waits()` reads `.claude-state/release-scope.json`: status `closed` + an excluded `<repo>#<n>` =
  `[PR|human]` with the version; an open scope stays the building session's work. Replay on the macOS brain:
  standing 23 -> 2, human 0 -> 21. Fixture: `scripts/test-open-items.sh` (+3 cases, red before the fix).
