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
  - Exit and PR list disagreeing is said, not read as plain own work (measured the same day: seven entries carried by open
    PRs stood as `ai-does-it` because the exit was never moved when the PR opened; one `in-pr` exit named no PR and read as
    "no open PR any more"; one named its PR on the continuation line and was missed). The reader takes the last exit
    WITH its continuation lines plus the `check:` line, matches PR numbers and the open PRs' head branches
    (`headRefName` joins the query): `in-pr` + open PR = waiting as before; `in-pr` with no reference says "names no PR
    at all"; `ai-does-it` naming an open PR says "its exit says ai-does-it, but <PR> is open — write in-pr if the PR
    carries the rest" and stays the agent's (the writer decides). Fixture +4, all four red on the old reader.
  - Our own open check request names the PR: the PR waits on the request's `next` for one day, then it is ours again
    with "our check request of <date> to <next> has no answer - ask that machine by name" (operator rule 2026-10-21).
    `shared_answers.own_open_requests()` reads frontmatter `von` = this device, `status: open`, PRs as `<repo>#N [#M …]`
    in `description`. Measured the same day: three own PRs waiting on a Windows check were printed as our move. Fixture +4.
  - `suite-check.py`: a pin on a tag missing from a single-branch clone (fetch refspec names one branch) is WARN
    "unchecked (git fetch --tags)", not "is no tag of this repo" — the push lint of a fresh `--single-branch` clone went red
    on v2.0.0, which origin has. Offline on purpose: an `ls-remote` variant cost ~45 s of fixture time. Fixture +2.
