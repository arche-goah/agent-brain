#!/usr/bin/env python3
"""repo-activity-filter.py -- turn one raw GitHub answer into event lines + a cursor line.

Called by scripts/repo-activity-watch.sh once per repo and channel, with the JSON on stdin:

  gh api repos/<o>/<r>/issues/comments?since=... | repo-activity-filter.py comments <o>/<r> <since> <self> <only>
  gh pr list --json number,title,author,createdAt,headRefName | ... open   <o>/<r> <since> <self> <only>
  gh pr list --json number,title,mergedBy,mergedAt,headRefName | ... merged <o>/<r> <since> <self> <only>

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

Output: event lines; lines that carry a branch are "<branch>\\t<text>" so the caller can
mark branches that exist in the local clone; last line "CURSOR <newest timestamp>".
"""
from __future__ import annotations

import json
import sys

sys.stdout.reconfigure(encoding="utf-8", newline="\n")  # parsed by bash (OS-9)

TS = {"comments": "created_at", "open": "createdAt", "merged": "mergedAt"}


def login(obj) -> str:
    return (obj or {}).get("login") or "?"


def main(argv: list) -> int:
    if len(argv) != 6 or argv[1] not in TS:
        print("usage: repo-activity-filter.py <comments|open|merged> <owner/repo> <since> <self> <only>",
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
    for it in items:
        ts = it.get(key) or ""
        if ts <= since:
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
