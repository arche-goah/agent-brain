- **collab watch: a red CI run of an older head is no CI-RED once a newer run of the same workflow stands on its branch** (test: T1) (level: reader; higher: writer — GitHub writes the runs; debt: the line still names the branch, not the head sha)
  Measured 2026-11-10 (heavy-metal #124, reported by the heavy-metal session): run 42881244627 failed on head 076f1e8
  (19:02 UTC); after the push to 08239f8 its run 42881934124 passed (19:06) — the watch still reported the old failure
  as `CI-RED … on lab-2026-11-10`, in two sessions. `superseded()` applied to cancelled runs only; it now applies to every
  red conclusion. A red run that is still the newest on its branch is reported as before. Fixture:
  `scripts/test-repo-activity-watch.sh` (a failed run followed by a green one on the same branch stays silent).
