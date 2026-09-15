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
  review — someone else's PR you are involved in (you reviewed it before, a review was
           requested from you, or its body @-mentions you), with a commit newer than your
           last review or comment (the author is waiting on you)
Only PRs whose move has been open for at least --min-hours count; drafts never do.

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


def moves(data, now, min_hours):
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
        if hours >= min_hours:
            out.append((hours, f"{name} {kind}, {int(hours)} h"))
    return [text for _, text in sorted(out, reverse=True)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--now", help="ISO time, default: now (for fixtures)")
    ap.add_argument("--min-hours", type=float, default=24)
    a = ap.parse_args()
    now = ts(a.now) if a.now else datetime.now(timezone.utc)
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0  # offline / gh error / no JSON: silence, never a false line
    found = moves(data, now, a.min_hours)
    if found:
        # ASCII only: Python prints through the console code page on Windows, and a dash
        # or middle dot arrived there as a replacement character (Windows runner, 2026-09-15).
        print("!! PR waiting on you: " + " | ".join(found[:6]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
