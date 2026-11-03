- **Open items: the PR search reads every page; a cut list is a failed read** (test: T1) (level: reader; higher: none —
  the search is the source, the reader cut it; debt: none). Measured on the macOS instance 2026-11-03: 59 open PRs
  against a search page of 50; the nine beyond it fell off silently, and two ledger entries carried by an open suite PR
  printed as "its in-pr exit names no open PR any more" for 17 and 21 sessions.
  - `scripts/open-items.py`: the GraphQL search pages with `after` (up to 20 pages of 50); fewer rows than the search's
    `issueCount` makes the PR search an unread source instead of a short list. The fixture hook takes one file per page,
    joined by `os.pathsep`. Fixture +2 (second page listed; a missing page = unread).
