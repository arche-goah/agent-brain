#!/usr/bin/env python3
"""repo-activity-filter.py -- turn one raw GitHub answer into event lines + a cursor line.

Called by scripts/repo-activity-watch.sh once per repo and channel, with the JSON on stdin:

  gh api repos/<o>/<r>/issues/comments?since=... | repo-activity-filter.py comments <o>/<r> <since> <self> <only>
  gh pr list --json number,title,author,createdAt,headRefName | ... open   <o>/<r> <since> <self> <only>
  gh pr list --json number,title,mergedBy,mergedAt,headRefName | ... merged <o>/<r> <since> <self> <only>
  gh run list --json workflowName,event,headBranch,status,conclusion,createdAt,updatedAt,url
                                                              | ... runs   <o>/<r> <since> <self> <only>

WHY PYTHON AND NOT `gh --jq`: the filter is the one place a watch can look armed and be
blind, so it needs a fixture on every OS -- and a fixture can fake `gh` (it is just a
program on PATH) but cannot fake gh's built-in jq, and a standalone jq is missing on a
stock Windows workstation. Raw JSON in, lines out, testable everywhere.

Rules carried here, each one measured on the proving instance:
  * `since` is INCLUSIVE on GitHub's side, and the cursor is the newest timestamp seen --
    without the strict `>` below the newest comment re-enters every round and is reported
    forever. Repeat noise trains the reader to ignore the watcher.
  * <self> defaults to "-" (a login that cannot match): one operator's machines share ONE
    account, so an author filter swallows exactly the other own machine's contributions.
  * A MERGE is judged by `mergedBy`, never by `author`: the other party merging OUR pull
    request is the event wanted, and an author filter would drop it.
  * The CURSOR line covers every item GitHub returned, reported or filtered -- a filtered
    event is gone for good, also after the filter is lifted. That price is stated, not hidden.
  * `runs` reports RED runs only (CI-RED lines) and ignores the login filters: a red check
    on a watched repo is the finding whoever pushed. Its cursor is the newest `updatedAt`
    of a COMPLETED run -- a running run stamps itself again when it ends, so it re-enters.
    A cancelled run superseded by a newer run of the same workflow on the same branch is
    GitHub's concurrency at work and stays silent; a cancelled run that is still the newest
    is reported (the 2026-10-13 case: a macOS job that never got a runner).

Output: event lines; lines that carry a branch are "<branch>\\t<text>" so the caller can
mark branches that exist in the local clone; last line "CURSOR <newest timestamp>".
"""
from __future__ import annotations

import json
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", newline="\n")  # parsed by bash (OS-9)

TS = {"comments": "created_at", "open": "createdAt", "merged": "mergedAt", "runs": "updatedAt"}

# Every terminal state of a workflow run that is not green. `cancelled` is in: a run whose
# macOS job never got a runner ends as cancelled, not failed (measured 2026-10-13, core PR
# #267: red for fifteen minutes, found by the operator, because the only watcher was the
# per-PR ci-watch nobody had armed for that push).
RED = {"failure", "cancelled", "timed_out", "startup_failure", "action_required"}


def login(obj) -> str:
    return (obj or {}).get("login") or "?"


def pushes(items: list, repo: str, self_login: str, only_set: set) -> None:
    """New commits on a PR that was already open. Measured 2026-11-01 on the macOS instance: a
    collaborator's AI pushed a commit to an open PR (the public marketplace pins) and the watch
    said nothing - `open` keys on `createdAt`, which a push does not move; the operator reported
    it by hand. The heads of the open PRs are kept in $REPO_ACTIVITY_HEADS (a JSON file the
    caller owns); a PR seen for the first time is stored, not reported, so arming the watch
    floods nothing. The PR's author is the filter (who pushed is not in the list answer)."""
    path = os.environ.get("REPO_ACTIVITY_HEADS")
    if not path:
        return
    try:
        with open(path, encoding="utf-8") as f:
            heads = json.load(f)
    except (OSError, ValueError):
        heads = {}
    for it in items:
        oid = it.get("headRefOid")
        if not oid:
            continue
        k = f"{repo}#{it.get('number')}"
        old = heads.get(k)
        # A draft turned ready is the author's "done" - the event a merger waits for, and it moves no
        # `createdAt` either (same class as the push, swept 2026-11-01). Kept as "<oid> draft".
        draft = bool(it.get("isDraft"))
        heads[k] = oid + (" draft" if draft else "")
        who = login(it.get("author"))
        if not old or who == self_login or (only_set and who not in only_set):
            continue
        old_oid, was_draft = old.split(" ")[0], old.endswith(" draft")
        if old_oid != oid:
            print(f"{it.get('headRefName', '')}\tPUSH {repo} #{it.get('number')}: {it.get('title', '')} "
                  f"(new head {oid[:7]}, was {old_oid[:7]}; PR by {who})")
        if was_draft and not draft:
            print(f"{it.get('headRefName', '')}\tREADY {repo} #{it.get('number')}: {it.get('title', '')} "
                  f"(draft marked ready for review; PR by {who})")
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(heads, f, indent=0, sort_keys=True)
    except OSError:
        print(f"WATCH-ERROR: cannot write the PR heads to {path} - new commits on open PRs are NOT reported")


def superseded(run: dict, runs: list) -> bool:
    """A cancelled run is noise when a NEWER run of the same workflow on the same branch
    exists: GitHub's concurrency cancels the older push's run on purpose (two merges a
    minute apart). A cancelled run that is still the newest on its branch is the real
    thing — nobody re-ran it, the branch sits red."""
    return any(o is not run
               and o.get("workflowName") == run.get("workflowName")
               and o.get("headBranch") == run.get("headBranch")
               and (o.get("createdAt") or "") > (run.get("createdAt") or "")
               for o in runs)


def red_runs(items: list, repo: str, since: str) -> None:
    """One line per red run newer than the cursor. No login filter here on purpose: a red
    run on a watched repo concerns whoever watches it, whichever account pushed."""
    for it in items:
        if (it.get("updatedAt") or "") <= since or it.get("status") != "completed":
            continue
        concl = it.get("conclusion") or ""
        if concl not in RED or (concl == "cancelled" and superseded(it, items)):
            continue
        br = it.get("headBranch") or ""
        print(f"{br}\tCI-RED {repo} {it.get('workflowName', '?')} on {br} "
              f"({it.get('event', '?')}, {concl}) {it.get('url', '')}")


def main(argv: list) -> int:
    if len(argv) != 6 or argv[1] not in TS:
        print("usage: repo-activity-filter.py <comments|open|merged|runs> <owner/repo> <since> <self> <only>",
              file=sys.stderr)
        return 64
    mode, repo, since, self_login, only = argv[1:]
    only_set = set(only.split()) - {"-"}
    raw = sys.stdin.read().strip()
    if not raw:
        return 0  # gh failed or answered nothing; reachability is probed by the caller
    try:
        items = json.loads(raw)
        if not isinstance(items, list):
            raise ValueError("not a list")
    except ValueError:
        print(f"WATCH-ERROR: unreadable answer for {repo} ({mode})")
        return 0

    key = TS[mode]
    if mode == "open":
        pushes(items, repo, self_login, only_set)
    if mode == "runs":
        red_runs(items, repo, since)
        items = [it for it in items if it.get("status") == "completed"]  # a running run moves its stamp again
    for it in items:
        ts = it.get(key) or ""
        if ts <= since or mode == "runs":
            continue
        if mode == "comments":
            who = login(it.get("user"))
        elif mode == "open":
            who = login(it.get("author"))
        else:
            who = login(it.get("mergedBy"))
        if who == self_login or (only_set and who not in only_set):
            continue
        if mode == "comments":
            body = " ".join((it.get("body") or "").split())[:160]
            print(f"COMMENT {repo} {it.get('html_url', '')} [{who}] {ts} :: {body}")
        elif mode == "open":
            print(f"{it.get('headRefName', '')}\tPR {repo} #{it.get('number')}: {it.get('title', '')} ({who})")
        else:
            print(f"{it.get('headRefName', '')}\tMERGED {repo} #{it.get('number')}: "
                  f"{it.get('title', '')} (merged by {who})")

    newest = max((it.get(key) or "" for it in items), default="")
    if newest:
        print(f"CURSOR {newest}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
