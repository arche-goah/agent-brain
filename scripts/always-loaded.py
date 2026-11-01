#!/usr/bin/env python3
"""always-loaded.py — has the context every session loads grown since the last accepted review?

WHY (proving brain 2026-10-08): CLAUDE.md had crept to 258 lines with state, todos and history
that belong in ledgers; a recurring diet review cut it back, but nothing showed the creep
between reviews — growth costs every session and never fails. A bare line limit on CLAUDE.md
misses the rule files and the memory index loaded beside it, so the measure is the TOTAL:
CLAUDE.md + .claude/rules/*.md + core/rules/*.md + the MEMORY.md index.

The baseline is ACCEPTED, not rolled: `--accept` sets it (at the diet review). Every start
compares against it, so slow creep adds up instead of hiding in small daily steps.

The baseline is one half. The other is the HARD limit: Claude Code stops loading the
always-loaded set above about 150 000 characters, and nothing says so when it happens
(measured 2026-10-11 on the proving brain: the baseline warning said "+16 KB", the cut
stood only in a harness message nobody reads). So a second line names the distance to that
limit, independent of the baseline, from 90 % on, and says "OVER" above it.

Usage: always-loaded.py [--repo DIR] [--memory FILE] [--accept] [--slack BYTES] [--limit BYTES]
Output: nothing while within the slack (default 2048 bytes) of the baseline, below 90 % of the
limit (default 150000), or when no baseline exists yet (it is created silently); otherwise one
line per finding. Exit 0 always.
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
    ap.add_argument("--limit", type=int, default=150000)
    a = ap.parse_args(argv)
    if a.memory and os.path.isdir(a.memory):
        # a directory sizes as 0 or as its entry table, never the index (Windows check
        # 2026-10-09: a folder passed by hand "grew" 6 KB seconds after the baseline)
        print(f"always-loaded: --memory must be the MEMORY.md file, not a directory: {a.memory}")
        return 0
    state = os.path.join(a.repo, ".claude-state", "always-loaded.json")
    now = measure(a.repo, a.memory)
    # The hard limit does not care about the baseline: say it first, even on the first run.
    # OS-9 (os-traps.md): the print line stays ASCII; the dash sits on the continuation line.
    if a.limit > 0 and now >= a.limit:
        print(f"always-loaded context is OVER the harness limit: {now} of {a.limit} bytes "
              "— the loader cuts what is above it and says nothing; diet NOW (rule-only text, incidents into the protocol)")
    elif a.limit > 0 and now * 10 >= a.limit * 9:
        print(f"always-loaded context is at {now} of {a.limit} bytes ({now * 100 // a.limit} % of the harness limit) "
              "— diet before the next rule, not after")
    try:
        with open(state, encoding="utf-8") as f:
            base = json.load(f)
    except (OSError, ValueError):
        base = None
    if a.accept or not base:
        try:
            os.makedirs(os.path.dirname(state), exist_ok=True)
            with open(state, "w", encoding="utf-8", newline="\n") as f:
                json.dump({"bytes": now, "date": datetime.date.today().isoformat(),
                           "memory": bool(a.memory)}, f)
        except OSError:
            pass
        if a.accept:
            print(f"always-loaded baseline set: {now} bytes")
        return 0
    # A baseline accepted over a different file set is no baseline: `--accept` typed by hand
    # without --memory, then the session start measuring with it, reported the whole memory
    # index as growth (+22 KB, macOS instance 2026-10-27). Say which half is missing instead.
    if "memory" in base and bool(base["memory"]) != bool(a.memory):
        print(f"always-loaded baseline of {base.get('date', '?')} was accepted "
              f"{'with' if base['memory'] else 'without'} the memory index and this run measures "
              f"{'without' if base['memory'] else 'with'} it — no growth figure; re-accept with the "
              "same arguments the session start uses (always-loaded.py --memory <MEMORY.md> --accept)")
        return 0
    grown = now - int(base.get("bytes", now))
    if grown > a.slack:
        # "from X to Y", not "X -> Y": the session start escapes > for its own wrapper, so the
        # arrow reached the operator as "-&gt;" (measured 2026-10-11).
        print(f"always-loaded context grew from {base['bytes']} to {now} bytes (+{grown}) since the review of {base.get('date', '?')} "
              "— a new rule, or state/todo/history that belongs in a ledger? Diet review, then always-loaded.py --accept")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
