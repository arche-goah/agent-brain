- **Open items: the PR search reads every page; a cut list is a failed read** (test: T1) (level: reader; higher: none —
  the search is the source, the reader cut it; debt: none). Measured on the macOS instance 2026-11-03: 59 open PRs
  against a search page of 50; the nine beyond it fell off silently, and two ledger entries carried by an open suite PR
  printed as "its in-pr exit names no open PR any more" for 17 and 21 sessions.
  - `scripts/open-items.py`: the GraphQL search pages with `after` (up to 20 pages of 50); fewer rows than the search's
    `issueCount` makes the PR search an unread source instead of a short list. The fixture hook takes one file per page,
    joined by `os.pathsep`. Fixture +2 (second page listed; a missing page = unread).
  - The same class at three more sites: the bootup's PR search for `pr-ball.py` read 40 (now 100 and its `issueCount`;
    `pr-ball.py` names a cut search: "PR search cut: n of m"); `release-preflight.sh` read gh's default of 30 open PRs
    for the competing-release and beta-candidate checks (now `--limit 1000`); `repo-activity-watch.sh` read 50 open PRs
    per repo with 49 open in the core (now 1000). Class guard in `test-pr-ball.sh`: every `gh pr list` in helpers/ and
    scripts/ names its `--limit` (red on the old preflight, two hits). Fixture +4.
