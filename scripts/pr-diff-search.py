#!/usr/bin/env python3
"""Search a pattern over the diffs of a repo's open PRs - the class search before a fix includes the open PRs.

WHY (measured 2026-11-23 on the macOS instance): core PR #645 fixed what the open #618 had already fixed. The
class search ran over the checked-out tree (main), and an open PR's change is not in that tree; PRS-FIRST
(helpers/pr-overlap-gate.cjs) named the open PRs by title, and a title does not say which lines a PR changes.

Usage:
  python3 scripts/pr-diff-search.py <regex> [-R owner/repo] [-i]
Prints one line per changed line that matches: `#<nr> <path>:<line> <+|-> <text>` (line = new-side number for
`+`, old-side for `-`), then a summary. Only added and removed lines are searched, never context.
Exit: 0 = at least one hit, 1 = no hit, 2 = error (gh missing, repo unknown, bad regex, or no hit while a PR's
diff was unreadable - that PR was not searched) - like grep.
The repo defaults to the origin of the current directory's git repo.
Git Bash on Windows rewrites an argument that starts with `/` into a Windows path before Python sees it (MSYS path
conversion): `'/tmp/out'` arrives as `C:/Program Files/Git/tmp/out` and gives "no hit". Write `'[/]tmp/out'`, or
run from PowerShell, which passes it unchanged (Windows review 2026-11-26). A PR whose diff cannot be read is named
and skipped; the others are still searched, and the summary names the skipped ones.
Test fixture via PR_DIFF_FIXTURE (path to JSON {"repo": ..., "prs": [{"number", "title", "diff"}]}; a PR with
"unreadable": true stands for one whose diff could not be read).
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
    # `---` / `+++` are headers only OUTSIDE a hunk: inside one, a removed `-- comment` or an added `++ x` line is
    # content (Windows review 2026-11-26: such a line was read as a header, its hit lost, the path replaced). A hunk
    # ends when its counts from the `@@` header are used up. split("\n"), not splitlines(): a form feed or U+2028 in
    # a changed line must not start a new line. `diff --git ` ends any hunk without condition: hunk content starts
    # with space, `+`, `-` or `\`, never `d`, and a truncated or miscounted hunk would otherwise swallow the next
    # file's header and print its hits under the previous path (Windows review 2026-11-27).
    path, old, new, old_left, new_left = None, 0, 0, 0, 0
    for raw in diff.split("\n"):
        raw = raw[:-1] if raw.endswith("\r") else raw
        if raw.startswith("diff --git "):
            path, old_left, new_left = None, 0, 0
            continue
        in_hunk = old_left > 0 or new_left > 0
        if not in_hunk and raw.startswith("--- "):
            p = raw[4:].strip()
            path = None if p == "/dev/null" else (p[2:] if p.startswith("a/") else p)
        elif not in_hunk and raw.startswith("+++ "):
            p = raw[4:].strip()
            if p != "/dev/null":
                path = p[2:] if p.startswith("b/") else p
        elif raw.startswith("@@"):
            m = re.match(r"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))?", raw)
            if m:
                old, new = int(m.group(1)), int(m.group(3))
                old_left = int(m.group(2)) if m.group(2) is not None else 1
                new_left = int(m.group(4)) if m.group(4) is not None else 1
        elif in_hunk and raw.startswith("+"):
            if rx.search(raw[1:]):
                yield path, new, "+", raw[1:]
            new += 1
            new_left -= 1
        elif in_hunk and raw.startswith("-"):
            if rx.search(raw[1:]):
                yield path, old, "-", raw[1:]
            old += 1
            old_left -= 1
        elif in_hunk and raw.startswith(" "):
            old += 1
            new += 1
            old_left -= 1
            new_left -= 1


def load(repo):
    fx = os.environ.get("PR_DIFF_FIXTURE")
    if fx:
        with open(fx, encoding="utf-8") as f:
            d = json.load(f)
        return d.get("repo") or repo, d["prs"]
    prs = json.loads(gh(["pr", "list", "-R", repo, "--state", "open", "--limit", "200", "--json", "number,title"]))
    for p in prs:
        try:
            p["diff"] = gh(["pr", "diff", str(p["number"]), "-R", repo])
        except (OSError, subprocess.SubprocessError) as e:
            print(f"pr-diff-search: #{p['number']} diff not readable, skipped ({type(e).__name__})", file=sys.stderr)
            p["diff"], p["unreadable"] = "", True
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
    # A skipped PR is not searched: the summary counts only the read diffs and names the skipped ones, and "no hit"
    # with a skipped PR is exit 2 - the absence was not measured there (Windows review 2026-11-27).
    skipped = [f"#{p['number']}" for p in prs if p.get("unreadable")]
    searched = len(prs) - len(skipped)
    note = f" ({len(skipped)} not readable, skipped: {', '.join(skipped)})" if skipped else ""
    total, with_hits = 0, []
    for p in prs:
        if p.get("unreadable"):
            continue
        n = 0
        for path, line, sign, text in hits_in(p.get("diff") or "", rx):
            print(f"#{p['number']} {path}:{line} {sign} {text.strip()[:200]}")
            n += 1
        if n:
            with_hits.append(f"#{p['number']} {str(p.get('title', ''))[:60]} ({n})")
        total += n
    if total:
        print(f"{total} hit(s) in {len(with_hits)} of {searched} searched open PR(s) of {repo}{note}: "
              + "; ".join(with_hits))
        return 0
    print(f"no hit in the diffs of {searched} of {len(prs)} open PR(s) of {repo}{note}" if skipped
          else f"no hit in the diffs of {len(prs)} open PR(s) of {repo}")
    return 2 if skipped else 1


if __name__ == "__main__":
    sys.exit(main())
