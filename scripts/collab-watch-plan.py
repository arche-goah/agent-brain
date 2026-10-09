#!/usr/bin/env python3
"""collab-watch-plan.py -- turn the instance's collab-watch config plus a SCOPE into the
lines scripts/collab-watch.sh executes.

WHY A SEPARATE, TESTABLE STEP: which repos are watched, at which interval, and which
parties count as an event ARE the agreement between collaborators. Written as prose they
get re-derived every session and drift; hardcoded in a script they turn into constants
that outlive the situation they were written for (measured on the proving instance: a
scope named after a ROLE word carried one collaborator's login; when a second
collaborator joined, that scope would have dropped him silently -- and a dropped event
never comes back, because the watchers advance their cursors before any filter sees a
line). Here the data lives in ONE instance file and every rule about it is checked by
scripts/test-collab-watch-plan.sh.

Usage:  collab-watch-plan.py <config.json> <scope>
  scope = all | peers | <party label> | <party id> | <github login>   (case-insensitive)

Output, one directive per line (parsed by collab-watch.sh):
  SCOPE_LOGINS <logins to report, space-separated, or "-" = no filter>
  SCOPE_PARTIES <shared-memory party ids to report, or "-">
  SCOPE_LABEL <human text>
  SM <interval> <repo path, verbatim, may start with ~ and contain spaces>
  REPO <tag> <interval> <owner/name> [<owner/name> ...]
  SESSIONS <interval>

Exit 0 = plan printed, 1 = config unusable, 64 = scope refused.
"""
from __future__ import annotations

import json
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", newline="\n")  # parsed by bash (OS-9)

TEMPLATE = "core/templates/rules-instance/collab-watch.json"
TAG_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
MIN_INTERVAL = 30


def die(msg: str, rc: int = 1) -> int:
    print(f"ERROR: {msg}", file=sys.stderr)
    return rc


def placeholder(value) -> bool:
    return isinstance(value, str) and "<" in value and ">" in value


def interval(block: dict, where: str) -> int:
    val = block.get("interval")
    if not isinstance(val, int) or val < MIN_INTERVAL:
        raise ValueError(f"{where}: interval must be an integer >= {MIN_INTERVAL}, got {val!r}")
    return val


def resolve_scope(parties: list, scope: str):
    """Return (logins, party_ids, label) or raise LookupError/PermissionError."""
    if scope == "all":
        # No filter at all: every party, the operator's own other machines included.
        return "-", "-", "all parties (no filter)"
    s = scope.lower()
    if s == "peers":
        selected = [p for p in parties if p["kind"] == "peer"]
    else:
        # A label names a PERSON, and one person can write from several machines --
        # select every id under it, or the second machine is filtered away silently.
        selected = [p for p in parties if p["label"].lower() == s]
        if not selected:
            selected = [p for p in parties if s in (p["id"].lower(), p["github"].lower())]
    if not selected:
        names = sorted({p["label"].lower() for p in parties if p["kind"] == "peer"})
        raise LookupError(f"unknown scope {scope!r} -- use: all, peers, " + ", ".join(names))
    if any(p["kind"] == "self" for p in selected):
        raise PermissionError(
            "a scope that selects one of the operator's own machines cannot work -- they "
            "push under one account, a login filter cannot tell them apart")
    logins = " ".join(sorted({p["github"] for p in selected}))
    ids = " ".join(sorted({p["id"] for p in selected}))
    label = ", ".join(sorted({p["label"] for p in selected})) + " only"
    return logins, ids, label


def main(argv: list) -> int:
    if len(argv) != 3 or not argv[2]:
        return die("usage: collab-watch-plan.py <config.json> <all|peers|party>", 64)
    path, scope = argv[1], argv[2]
    try:
        with open(path, encoding="utf-8") as fh:
            cfg = json.load(fh)
    except OSError:
        return die(f"no collab-watch config at {path} -- copy {TEMPLATE} into the "
                   "instance and fill it in")
    except ValueError as exc:
        return die(f"{path} is not valid JSON: {exc}")

    try:
        parties = cfg.get("parties", [])
        for p in parties:
            if not {"id", "github", "label", "kind"} <= set(p) or p["kind"] not in ("self", "peer"):
                raise ValueError(f"party entry incomplete or wrong kind (self|peer): {p}")
            if any(placeholder(v) for v in p.values()):
                raise ValueError(f"party entry still carries a template placeholder: {p}")

        lines = []
        sm = cfg.get("shared_memory")
        if sm:
            repo = sm.get("repo", "")
            if not repo or placeholder(repo):
                raise ValueError("shared_memory.repo is empty or still a template placeholder")
            lines.append(f"SM {interval(sm, 'shared_memory')} {repo}")

        seen_tags, seen_repos = set(), {}
        for i, w in enumerate(cfg.get("repo_watches", [])):
            tag = w.get("tag", "")
            if not TAG_RE.match(tag):
                raise ValueError(f"repo_watches[{i}].tag must be lowercase kebab-case, got {tag!r}")
            # The tag names the cursor and the lock. Two watches under one tag share both:
            # the faster one advances the cursor past events the slower one has not
            # reported yet, and the second to start refuses as a duplicate.
            if tag in seen_tags:
                raise ValueError(f"tag {tag!r} used twice -- two watches would share one cursor")
            seen_tags.add(tag)
            repos = w.get("repos", [])
            if not repos:
                raise ValueError(f"repo_watches[{i}] ({tag}) lists no repos")
            for r in repos:
                if placeholder(r) or not REPO_RE.match(r):
                    raise ValueError(f"repo_watches[{i}] ({tag}): {r!r} is not <owner>/<name>")
                if r in seen_repos:
                    raise ValueError(f"{r} is watched by both {seen_repos[r]!r} and {tag!r} -- "
                                     "every event would be reported twice")
                seen_repos[r] = tag
            lines.append(f"REPO {tag} {interval(w, tag)} " + " ".join(repos))

        ps = cfg.get("parallel_sessions")
        if ps:
            lines.append(f"SESSIONS {interval(ps, 'parallel_sessions')}")
        if not lines:
            raise ValueError("nothing to watch -- no shared_memory, repo_watches or parallel_sessions")
    except (ValueError, AttributeError, TypeError) as exc:
        return die(f"{path}: {exc}")

    try:
        logins, ids, label = resolve_scope(parties, scope)
    except (LookupError, PermissionError) as exc:
        return die(str(exc), 64)

    print(f"SCOPE_LOGINS {logins}")
    print(f"SCOPE_PARTIES {ids}")
    print(f"SCOPE_LABEL {label}")
    for line in lines:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
