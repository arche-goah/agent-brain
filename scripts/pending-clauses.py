#!/usr/bin/env python3
"""pending-clauses — find rule text that waits for a core state the pin already reached.

WHY: instance rules are full of conditions on the core — "once the pin carries it",
"until core PR #203 lands", "from core PR #162". They are true when written and turn
silently false when the pin moves: measured on the proving brain 2026-10-09, five such
clauses (an open order, a "not yet delivered" check, a "not active yet" bootup check, a
"from PR #203" end condition) all described states that core v1.4.0 had already ended, and
a session following them would reopen finished work or ignore a live check. Nothing
re-reads a rule when the pin moves, so the update is where the question has to be asked.

What it does: reads the instance's always-loaded rule text (CLAUDE.md, .claude/rules/**),
finds lines that match a pending-clause pattern, and for every `#<n>` on such a line asks
the CONSUMED core checkout (`core/`, the pinned state) whether a commit with "(#<n>)" in its
subject is in its history — squash merges carry the PR number there. In the pin = STALE,
the clause describes the past. A pending line without a PR number is listed for a reading.
Reports only, never edits: the wording of a rule is the instance's.

Patterns: English built in; other languages are instance data in
`.claude/rules/pending-clauses.json` ({"patterns": ["<regex>", ...]}, template shipped).

Usage: pending-clauses.py [--repo <instance root>] [--core <core checkout>]
Output: nothing when no pending clause is found; otherwise one line per clause and a
summary. Exit 0 always (a report, not a gate); 2 = unusable arguments.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

BUILTIN = [
    r"\bonce (?:the )?(?:core )?pin\b",
    r"\b(?:until|after|before) the (?:core )?pin\b",
    r"\bpending (?:core )?PR\b",
    r"\b(?:from|since|after|until) (?:core )?PR #\d+",
    r"\bPR #\d+ (?:lands|is merged|is pinned|ships)\b",
]


def load_patterns(repo):
    pats = list(BUILTIN)
    f = repo / ".claude" / "rules" / "pending-clauses.json"
    if f.is_file():
        try:
            pats += [p for p in json.loads(f.read_text(encoding="utf-8")).get("patterns", []) if isinstance(p, str)]
        except (OSError, ValueError) as e:
            print(f"pending-clauses: {f} unreadable ({e}) — built-in patterns only", file=sys.stderr)
    return [re.compile(p, re.IGNORECASE) for p in pats]


def rule_files(repo):
    out = []
    if (repo / "CLAUDE.md").is_file():
        out.append(repo / "CLAUDE.md")
    rules = repo / ".claude" / "rules"
    if rules.is_dir():
        # pending-clauses.json holds the patterns themselves: reading it would match itself.
        out += sorted(p for p in rules.rglob("*") if p.suffix in (".md", ".json")
                      and p.name != "pending-clauses.json")
    return out


def pr_in_pin(core, n, cache):
    if n not in cache:
        try:
            r = subprocess.run(["git", "-C", str(core), "log", "--format=%h", "-F", f"--grep=(#{n})", "-n", "1", "HEAD"],
                               capture_output=True, text=True, encoding="utf-8", timeout=20)
            cache[n] = r.stdout.strip() or None
        except (OSError, subprocess.SubprocessError):
            cache[n] = None
    return cache[n]


def main():
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")  # OS-9: callers parse this
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--repo", default=".")
    ap.add_argument("--core", default=None)
    a = ap.parse_args()
    repo = Path(a.repo).resolve()
    core = Path(a.core).resolve() if a.core else repo / "core"
    if not (core / ".git").exists():
        print(f"pending-clauses: no core checkout at {core} — nothing measured", file=sys.stderr)
        return 0
    try:
        tag = subprocess.run(["git", "-C", str(core), "describe", "--tags", "--always"],
                             capture_output=True, text=True, encoding="utf-8", timeout=20).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        tag = "?"
    pats = load_patterns(repo)
    cache, stale, unread = {}, [], []
    for f in rule_files(repo):
        try:
            lines = f.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        rel = f.relative_to(repo).as_posix()
        for i, line in enumerate(lines, 1):
            if not any(p.search(line) for p in pats):
                continue
            prs = [int(x) for x in re.findall(r"#(\d{1,6})\b", line)]
            hits = [(n, pr_in_pin(core, n, cache)) for n in prs]
            done = [f"#{n} ({c})" for n, c in hits if c]
            snippet = line.strip()[:110]
            if done:
                stale.append(f"  STALE {rel}:{i} — {', '.join(done)} already in the pinned core: {snippet}")
            elif not prs:
                unread.append(f"  READ  {rel}:{i} — pending clause without a PR number: {snippet}")
            else:
                # Not found is NOT "still open": a PR that reached the core through a
                # candidate/integration branch leaves no "(#n)" subject (measured
                # 2026-10-09: #162 and #203 were in v1.4.0 and invisible to the lookup).
                # A silent drop here would hide exactly the clauses this tool exists for.
                unread.append(f"  READ  {rel}:{i} — {', '.join('#' + str(n) for n in prs)} not provably in the "
                              f"pin (open, or merged via a candidate branch): {snippet}")
    if not stale and not unread:
        return 0
    print(f"pending clauses against the pinned core ({tag}):")
    for l in stale + unread:
        print(l)
    print(f"pending-clauses: {len(stale)} stale, {len(unread)} to read — turn each into the measured state "
          f"or drop the condition (the rule's wording is the instance's)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
