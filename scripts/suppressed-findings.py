#!/usr/bin/env python3
"""Suppression list for brain-scan findings: a finding the operator dropped on purpose stays out of the report until
its entry expires; an entry without a reason, without an expiry or past it is itself a finding.

WHY (audit-audit on the Windows instance, 2026-11-10, finding AA-16; released by the core owner the same day): of 78
scan keys over three runs, the INFO findings that each run regenerated and the report dropped again
(`effect-check-output-style-undeclared`, `mcp-spec-deprecations-upstream`) came back in every report — a decision
taken once was not remembered, so every run spent tokens and a reader's attention on it. A silent ignore list would
be the opposite failure: a finding hidden for good. So every entry carries why, who and until when, and the scan
says in one line how many it held back.

Instance data: <brain>/.claude/rules/suppressed-findings.json (template: templates/rules-instance/)
  {"entries": [{"key": "<scan key>", "pattern": "<regex on the finding title>", "reason": "...",
                "expires": "YYYY-MM-DD", "by": "<who decided, with date>"}]}
key and/or pattern: `key` matches a finding of an earlier report by its index key (the return channel), `pattern`
matches a raw finding's title (case-insensitive) - the machine checks here, the scan agents by the same rule.
An entry is active only while it is complete and `expires` >= today; any other entry suppresses nothing.

  suppressed-findings.py [--repo DIR] [--today YYYY-MM-DD]   list active entries and problems
Exit 0 always; brain-scan-prep.py imports load() and matches().
"""
import argparse
import datetime
import json
import re
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass

REL = Path(".claude/rules/suppressed-findings.json")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def load(repo, today):
    """(active entries, problems) - a problem is one line naming the entry and what is wrong with it."""
    p = Path(repo) / REL
    if not p.is_file():
        return [], []
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
        entries = data.get("entries", []) if isinstance(data, dict) else None
        if not isinstance(entries, list):
            raise ValueError("no entries list")
    except (OSError, ValueError) as e:
        return [], [f"{REL.as_posix()} unreadable ({e}) - nothing is suppressed"]
    active, problems = [], []
    for n, e in enumerate(entries, 1):
        if not isinstance(e, dict):
            problems.append(f"entry {n} is not an object")
            continue
        key, pat = str(e.get("key") or "").strip(), str(e.get("pattern") or "").strip()
        label = f"entry {n} ({key or pat or 'unnamed'})"
        bad = []
        if not key and not pat:
            bad.append("names neither key nor pattern")
        if pat:
            try:
                re.compile(pat)
            except re.error as err:
                bad.append(f"pattern does not compile ({err})")
        if not str(e.get("reason") or "").strip():
            bad.append("has no reason")
        if not str(e.get("by") or "").strip():
            bad.append("names no one who decided it (by)")
        exp = str(e.get("expires") or "").strip()
        if not DATE.match(exp):
            bad.append("has no expiry date (expires: YYYY-MM-DD)")
        elif exp < today:
            bad.append(f"expired on {exp}")
        if bad:
            problems.append(f"{label} {'; '.join(bad)} - it suppresses nothing until renewed with a reason or removed")
        else:
            active.append({"key": key, "pattern": pat, "reason": str(e["reason"]).strip(), "expires": exp,
                           "by": str(e["by"]).strip()})
    return active, problems


def matches(entry, key=None, title=""):
    if key and entry.get("key") and key == entry["key"]:
        return True
    return bool(entry.get("pattern")) and re.search(entry["pattern"], title or "", re.I) is not None


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--repo", default=".")
    ap.add_argument("--today", default=datetime.date.today().isoformat())
    a = ap.parse_args(argv)
    active, problems = load(a.repo, a.today)
    for e in active:
        print(f"active: {e['key'] or e['pattern']} until {e['expires']} ({e['by']}): {e['reason']}")
    for p in problems:
        print(f"!! suppressed-findings: {p}")
    print(f"suppressed-findings summary: {len(active)} active, {len(problems)} problem(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
