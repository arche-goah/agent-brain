- **content-review-gate: a PR's risk sets the model family that builds and reviews it, and an approval or merge needs a content review by another instance** (test: T1) (level: design; higher: none; debt: the model is read from the main session's transcript, so a build an agent commits is judged on the session's model, not the agent's)
  Operator orders 2026-11-10: review how a change is built and how it fits the whole, not only function and OS;
  judge reach, complexity and risk, and build and review at the matching model — nothing critical with a
  smaller one; below the minimum, hand the work to an agent or a session on that family; models matched by
  family so newer versions count at once. Measured before: no gate asked for a design verdict, and three PRs
  were approved that day on green fixtures, one carrying a second copy of a dispatcher rule. The gate holds
  `git commit` in the core and `gh pr create` below the build minimum (risk = the body's `Risk:` line, never
  below the floor of the changed files), `gh pr review --approve` without `Fit:` / `Design:` / `Cost:` /
  `Model:` (the model measured from the transcript), and `gh pr merge` without such a review by an instance
  other than the author (merge trains per member). Data `pr-risk.json`, questions `docs/content-review.md`,
  rule `rules/intelligence.md` § Model Routing. Fixture: `scripts/test-content-review-gate.sh` (26 cases).
