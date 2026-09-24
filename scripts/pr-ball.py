#!/usr/bin/env python3
"""pr-ball.py — whose move is each open PR, and for how long? One bootup line or silence.

WHY (measured 2026-09-15, core PRs #143/#144): a maintainer review requested changes on a
collaborator's PR; two days later nothing had moved. Both sides had a session-start line
about the ecosystem — "open PRs" named the titles, the shared-memory check named the new
commits and files — and neither said "the next move is yours". Awareness of NEWNESS was
there, awareness of an OBLIGATION was not, so the round-trip stalled with both sides
believing they were waiting on the other.

The line answers one question per PR, from the viewer's side, from GitHub's own state:
  yours  — your PR, and the newest review by someone else requested changes AFTER your
           last commit (the reviewer is waiting on you)
  yours  — your PR, and someone else reviewed or commented after your last commit and
           your last comment (a reply is waiting to be read: an OK to merge, a question)
  review — someone else's PR you are involved in (you reviewed it before, a review was
           requested from you, or its body @-mentions you), with a commit newer than your
           last review or comment (the author is waiting on you)
Every open move is named; drafts never are. Moves open --stall-hours or longer escalate
the line to `!!`.

WHY the reply case and no minimum age (measured 2026-09-22, core PRs #149/#150): a
collaborator posted "OK for merge" as a COMMENT on both, the only kind of review the
ruleset leaves them. The line knew only a CHANGES_REQUESTED review, and only after 24 h,
so the session starting four hours later was told nothing and the operator had to ask.
A move is an obligation from the moment it exists; age decides only how loud it is.

Input: the JSON of the GraphQL query in helpers/session-bootup.sh on stdin (viewer + search
nodes). Output: nothing, or ONE line. Exit 0 always — a bootup line never blocks a start.
"""
import argparse
import json
import sys
from datetime import datetime, timezone


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None


def nodes(obj, key):
    return ((obj or {}).get(key) or {}).get("nodes") or []


def login(obj):
    return ((obj or {}).get("login") or "").lower()


def is_bot(name):
    return name.endswith("[bot]") or name in ("github-actions", "dependabot")


def moves(data, now):
    me = login((data.get("data") or {}).get("viewer"))
    if not me:
        return []
    out = []
    for pr in nodes((data.get("data") or {}), "search"):
        if not pr or pr.get("isDraft"):
            continue
        name = f'{(pr.get("repository") or {}).get("name", "?")}#{pr.get("number")}'
        commits = nodes(pr, "commits")
        last_commit = ts(((commits[-1] if commits else {}).get("commit") or {}).get("committedDate"))
        reviews = [r for r in nodes(pr, "reviews") if r and r.get("submittedAt")]
        author = login(pr.get("author"))
        since, kind = None, None
        if author == me:
            others = sorted((r for r in reviews if login(r.get("author")) not in ("", me)),
                            key=lambda r: ts(r["submittedAt"]))
            if others and others[-1].get("state") == "CHANGES_REQUESTED":
                at = ts(others[-1]["submittedAt"])
                if last_commit is None or at > last_commit:
                    since, kind = at, "yours - changes requested"
            if since is None:
                comments = [c for c in nodes(pr, "comments") if c and c.get("createdAt")]
                theirs = [ts(r["submittedAt"]) for r in others] + [
                    ts(c["createdAt"]) for c in comments
                    if login(c.get("author")) not in ("", me) and not is_bot(login(c.get("author")))]
                seen = [t for t in [last_commit] + [ts(c["createdAt"]) for c in comments
                                                    if login(c.get("author")) == me] if t]
                if theirs and (not seen or max(theirs) > max(seen)):
                    since, kind = max(theirs), "yours - reply since your last commit"
        else:
            mine = [ts(r["submittedAt"]) for r in reviews if login(r.get("author")) == me]
            touched = mine + [ts(c.get("createdAt")) for c in nodes(pr, "comments")
                              if c and login(c.get("author")) == me and c.get("createdAt")]
            requested = any(login(n.get("requestedReviewer")) == me for n in nodes(pr, "reviewRequests") if n)
            mentioned = f"@{me}" in (pr.get("body") or "").lower()
            if (mine or requested or mentioned) and last_commit is not None:
                last_touch = max(touched) if touched else None
                if last_touch is None or last_commit > last_touch:
                    since, kind = last_commit, "review - new commits since your last look" if last_touch else "review - asked, not looked at yet"
        if since is None:
            continue
        hours = (now - since).total_seconds() / 3600
        out.append((hours, f"{name} {kind}, {int(hours)} h"))
    return sorted(out, reverse=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--now", help="ISO time, default: now (for fixtures)")
    ap.add_argument("--stall-hours", type=float, default=24)
    a = ap.parse_args()
    now = ts(a.now) if a.now else datetime.now(timezone.utc)
    try:
        data = json.load(sys.stdin)
    except Exception:
        # The bootup reports a failed gh call itself; here no JSON stays silence.
        return 0
    found = moves(data, now)
    if found:
        # ASCII only: Python prints through the console code page on Windows, and a dash
        # or middle dot arrived there as a replacement character (Windows runner, 2026-09-15).
        loud = "!! " if found[0][0] >= a.stall_hours else ""
        print(loud + "PR waiting on you: " + " | ".join(text for _, text in found[:6]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
