#!/usr/bin/env python3
"""always-loaded.py — has the context every session loads grown since the last accepted review?

WHY (proving brain 2026-10-08): CLAUDE.md had crept to 258 lines with state, todos and history
that belong in ledgers; a recurring diet review cut it back, but nothing showed the creep
between reviews — growth costs every session and never fails. A bare line limit on CLAUDE.md
misses the rule files and the memory index loaded beside it, so the measure is the TOTAL:
CLAUDE.md + .claude/rules/*.md + core/rules/*.md + the MEMORY.md index.

The baseline is ACCEPTED, not rolled: `--accept` sets it (at the diet review). Every start
compares against it, so slow creep adds up instead of hiding in small daily steps.

Usage: always-loaded.py [--repo DIR] [--memory FILE] [--accept] [--slack BYTES]
Output: nothing while within the slack (default 2048 bytes) of the baseline or when no
baseline exists yet (it is created silently); otherwise one line. Exit 0 always.
State: <repo>/.claude-state/always-loaded.json
"""
import argparse
import datetime
import glob
import json
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass


def measure(repo, memory):
    files = [os.path.join(repo, "CLAUDE.md")]
    files += sorted(glob.glob(os.path.join(repo, ".claude", "rules", "*.md")))
    files += sorted(glob.glob(os.path.join(repo, "core", "rules", "*.md")))
    if memory:
        files.append(memory)
    total = 0
    for f in files:
        try:
            total += os.path.getsize(f)
        except OSError:
            pass
    return total


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--memory", default="")
    ap.add_argument("--accept", action="store_true")
    ap.add_argument("--slack", type=int, default=2048)
    a = ap.parse_args(argv)
    state = os.path.join(a.repo, ".claude-state", "always-loaded.json")
    now = measure(a.repo, a.memory)
    try:
        with open(state, encoding="utf-8") as f:
            base = json.load(f)
    except (OSError, ValueError):
        base = None
    if a.accept or not base:
        try:
            os.makedirs(os.path.dirname(state), exist_ok=True)
            with open(state, "w", encoding="utf-8", newline="\n") as f:
                json.dump({"bytes": now, "date": datetime.date.today().isoformat()}, f)
        except OSError:
            pass
        if a.accept:
            print(f"always-loaded baseline set: {now} bytes")
        return 0
    grown = now - int(base.get("bytes", now))
    if grown > a.slack:
        print(f"always-loaded context grew {base['bytes']} -> {now} bytes (+{grown}) since the review of {base.get('date', '?')} "
              "— a new rule, or state/todo/history that belongs in a ledger? Diet review, then always-loaded.py --accept")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
