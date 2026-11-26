#!/usr/bin/env python3
"""Search a pattern over the diffs of a repo's open PRs - the class search before a fix includes the open PRs.

WHY (measured 2026-11-23 on the macOS instance): core PR #645 fixed what the open #618 had already fixed. The
class search ran over the checked-out tree (main), and an open PR's change is not in that tree; PRS-FIRST
(helpers/pr-overlap-gate.cjs) named the open PRs by title, and a title does not say which lines a PR changes.

Usage:
  python3 scripts/pr-diff-search.py <regex> [-R owner/repo] [-i]
Prints one line per changed line that matches: `#<nr> <path>:<line> <+|-> <text>` (line = new-side number for
`+`, old-side for `-`), then a summary. Only added and removed lines are searched, never context.
Exit: 0 = at least one hit, 1 = no hit, 2 = error (gh missing, repo unknown, bad regex) - like grep.
The repo defaults to the origin of the current directory's git repo.
Test fixture via PR_DIFF_FIXTURE (path to JSON {"repo": ..., "prs": [{"number", "title", "diff"}]}).
Test: scripts/pr-diff-search-test.py.
"""
import argparse
import json
import os
import re
import subprocess
import sys

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace", newline="\n")
    except (AttributeError, ValueError):
        pass


def gh(args):
    return subprocess.run(["gh"] + args, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", timeout=60, check=True).stdout


def origin_repo():
    try:
        url = subprocess.run(["git", "remote", "get-url", "origin"], capture_output=True, text=True,
                             timeout=10, check=True).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None
    m = re.search(r"github\.com[:/]([^/]+/[^/\s]+?)(?:\.git)?$", url)
    return m.group(1) if m else None


def hits_in(diff, rx):
    """Yield (path, line, sign, text) for every added or removed line of a unified diff that matches rx."""
    path, old, new = None, 0, 0
    for raw in diff.splitlines():
        if raw.startswith("diff --git "):
            path = None
        elif raw.startswith("--- "):
            p = raw[4:].strip()
            path = None if p == "/dev/null" else (p[2:] if p.startswith("a/") else p)
        elif raw.startswith("+++ "):
            p = raw[4:].strip()
            if p != "/dev/null":
                path = p[2:] if p.startswith("b/") else p
        elif raw.startswith("@@"):
            m = re.match(r"@@ -(\d+)(?:,\d+)? \+(\d+)", raw)
            if m:
                old, new = int(m.group(1)), int(m.group(2))
        elif raw.startswith("+"):
            if rx.search(raw[1:]):
                yield path, new, "+", raw[1:]
            new += 1
        elif raw.startswith("-"):
            if rx.search(raw[1:]):
                yield path, old, "-", raw[1:]
            old += 1
        elif raw.startswith(" "):
            old += 1
            new += 1


def load(repo):
    fx = os.environ.get("PR_DIFF_FIXTURE")
    if fx:
        with open(fx, encoding="utf-8") as f:
            d = json.load(f)
        return d.get("repo") or repo, d["prs"]
    prs = json.loads(gh(["pr", "list", "-R", repo, "--state", "open", "--limit", "200", "--json", "number,title"]))
    for p in prs:
        p["diff"] = gh(["pr", "diff", str(p["number"]), "-R", repo])
    return repo, prs


def main(argv=None):
    ap = argparse.ArgumentParser(description="Search a regex over the diffs of a repo's open PRs.")
    ap.add_argument("pattern")
    ap.add_argument("-R", "--repo")
    ap.add_argument("-i", "--ignore-case", action="store_true")
    a = ap.parse_args(argv)
    try:
        rx = re.compile(a.pattern, re.I if a.ignore_case else 0)
    except re.error as e:
        print(f"pr-diff-search: bad regex: {e}", file=sys.stderr)
        return 2
    repo = a.repo or origin_repo()
    if not repo and not os.environ.get("PR_DIFF_FIXTURE"):
        print("pr-diff-search: no repo (-R owner/repo, or run inside a clone)", file=sys.stderr)
        return 2
    try:
        repo, prs = load(repo)
    except (OSError, subprocess.SubprocessError, ValueError, KeyError) as e:
        print(f"pr-diff-search: could not read the open PRs: {e}", file=sys.stderr)
        return 2
    total, with_hits = 0, []
    for p in prs:
        n = 0
        for path, line, sign, text in hits_in(p.get("diff") or "", rx):
            print(f"#{p['number']} {path}:{line} {sign} {text.strip()[:200]}")
            n += 1
        if n:
            with_hits.append(f"#{p['number']} {str(p.get('title', ''))[:60]} ({n})")
        total += n
    if total:
        print(f"{total} hit(s) in {len(with_hits)} of {len(prs)} open PR(s) of {repo}: " + "; ".join(with_hits))
        return 0
    print(f"no hit in the diffs of {len(prs)} open PR(s) of {repo}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
