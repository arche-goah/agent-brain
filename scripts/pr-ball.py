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
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from instance_key import is_self, key_in, self_key  # noqa: E402
from shared_answers import checked_head, own_shared_shas, sibling_keys_same_os  # noqa: E402


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None


def nodes(obj, key):
    return ((obj or {}).get(key) or {}).get("nodes") or []


def login(obj):
    return ((obj or {}).get("login") or "").lower()


def is_bot(name):
    return name.endswith("[bot]") or name in ("github-actions", "dependabot")


def moves(data, now, my_key="", shared_shas=frozenset()):
    me = login((data.get("data") or {}).get("viewer"))
    if not me:
        return []
    same_os = sibling_keys_same_os() if my_key else set()

    # "Mine" is login AND instance key: one login can carry several instances (the operator's
    # other machine), and a node with another instance's key is THEIR move, not ours.
    def mine(node, text_field="body"):
        return is_self(login(node.get("author")), me, node.get(text_field), my_key)

    def other(node):
        who = login(node.get("author"))
        return bool(who) and not mine(node)

    out = []
    for pr in nodes((data.get("data") or {}), "search"):
        if not pr or pr.get("isDraft"):
            continue
        name = f'{(pr.get("repository") or {}).get("name", "?")}#{pr.get("number")}'
        commits = nodes(pr, "commits")
        head = (commits[-1] if commits else {}).get("commit") or {}
        last_commit = ts(head.get("committedDate"))
        reviews = [r for r in nodes(pr, "reviews") if r and r.get("submittedAt")]
        since, kind = None, None
        if mine(pr):
            others = sorted((r for r in reviews if other(r)), key=lambda r: ts(r["submittedAt"]))
            if others and others[-1].get("state") == "CHANGES_REQUESTED":
                at = ts(others[-1]["submittedAt"])
                if last_commit is None or at > last_commit:
                    since, kind = at, "yours - changes requested"
            if since is None:
                comments = [c for c in nodes(pr, "comments") if c and c.get("createdAt")]
                theirs = [ts(r["submittedAt"]) for r in others] + [
                    ts(c["createdAt"]) for c in comments
                    if other(c) and not is_bot(login(c.get("author")))]
                seen = [t for t in [last_commit] + [ts(c["createdAt"]) for c in comments
                                                    if mine(c)] if t]
                if theirs and (not seen or max(theirs) > max(seen)):
                    since, kind = max(theirs), "yours - reply since your last commit"
        else:
            my_reviews = [ts(r["submittedAt"]) for r in reviews if mine(r)]
            touched = my_reviews + [ts(c.get("createdAt")) for c in nodes(pr, "comments")
                                    if c and mine(c) and c.get("createdAt")]
            # A sibling of our OS looked at it (its key in the text): that look stands for ours.
            def same_os_look(node):
                return login(node.get("author")) == me and key_in(node.get("body") or "") in same_os
            touched += [ts(r["submittedAt"]) for r in reviews if same_os_look(r)]
            touched += [ts(c.get("createdAt")) for c in nodes(pr, "comments")
                        if c and c.get("createdAt") and same_os_look(c)]
            requested = any(login(n.get("requestedReviewer")) == me for n in nodes(pr, "reviewRequests") if n)
            mentioned = f"@{me}" in (pr.get("body") or "").lower()
            # Another instance under OUR login opened it: that is a hand-over between the
            # operator's machines, so it is our move just like a review request (measured
            # 2026-10-11: the other machine's test fix waited for a second OK nobody was shown).
            sibling = login(pr.get("author")) == me
            # Our answer naming THIS head in the shared memory is our look at it
            # (shared_answers.py) — the request asked for the answer there, not on the PR.
            if checked_head(head.get("oid"), shared_shas):
                continue
            if (my_reviews or requested or mentioned or sibling) and last_commit is not None:
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
    found = moves(data, now, self_key(), own_shared_shas())
    if found:
        # ASCII only: Python prints through the console code page on Windows, and a dash
        # or middle dot arrived there as a replacement character (Windows runner, 2026-09-15).
        loud = "!! " if found[0][0] >= a.stall_hours else ""
        print(loud + "PR waiting on you: " + " | ".join(text for _, text in found[:6]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
