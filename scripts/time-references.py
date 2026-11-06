#!/usr/bin/env python3
"""Every relative time reference this brain wrote, in one reviewable list.

Operator decision 2026-08-20 (proving instance): relative time wording is normal language and
should not cost a re-issued answer — but the claim "it is right anyway" needs a data set, not a
feeling. So the check records instead of blocking (`helpers/time-gate.cjs --record`, row TIME-GATE
in `.claude/rules/stop-checks.json`), and this reads the record back.

    python3 core/scripts/time-references.py            # last 7 days
    python3 core/scripts/time-references.py --days 30
    python3 core/scripts/time-references.py --phrase yesterday
    python3 core/scripts/time-references.py --unanchored

What this CAN show: which wording appears how often, in which sentence, and whether the same
reply carried a hard time anchor (ISO date, commit, clock time) — the cheap signal that the
sentence was written from timestamps rather than from memory.

What it CANNOT show: whether a reference was TRUE. That still needs a look at the source, and
the sentence is printed precisely so that look is one step, not a hunt. Every violation measured
on the proving instance came from a reference DERIVED from a memory note, and those show up here
as un-anchored.

The log is `<brain>/.claude-state/time-gate.jsonl` (the stop dispatcher's recorder file for the
marker TIME-GATE) plus its rotated `.1.jsonl`. Brain root: --root, else $CLAUDE_PROJECT_DIR,
else the current directory.
Exit 0 always — a report, not a verdict.
"""
import argparse
import collections
import json
import os
import sys
from datetime import datetime, timedelta, timezone

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass


def rows_of(paths):
    for p in paths:
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    line = line.strip()
                    if line:
                        try:
                            yield json.loads(line)
                        except ValueError:
                            continue
        except OSError:
            continue


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    ap.add_argument("--days", type=int, default=7, help="how far back (default 7)")
    ap.add_argument("--phrase", help="only this wording")
    ap.add_argument("--unanchored", action="store_true",
                    help="only replies without a hard time anchor - the ones worth checking first")
    args = ap.parse_args(argv)

    state = os.path.join(args.root, ".claude-state")
    logs = [os.path.join(state, n) for n in ("time-gate.1.jsonl", "time-gate.jsonl")]
    if not any(os.path.exists(p) for p in logs):
        print(f"no record yet: {logs[-1]}")
        print("The recorder writes on every turn that contains a relative time reference, "
              "once the TIME-GATE row runs; an absent file means there were none, or the row is not wired.")
        return 0

    cutoff = datetime.now(timezone.utc) - timedelta(days=args.days)
    rows = []
    for d in rows_of(logs):
        try:
            when = datetime.fromisoformat(str(d["at"]).replace("Z", "+00:00"))
        except (KeyError, ValueError):
            continue
        if when.tzinfo is None:
            when = when.replace(tzinfo=timezone.utc)
        if when < cutoff:
            continue
        if args.phrase and args.phrase.lower() not in str(d.get("phrase", "")).lower():
            continue
        if args.unanchored and d.get("anchored"):
            continue
        rows.append((when, d))

    if not rows:
        print("nothing recorded in this window")
        return 0

    phrases = collections.Counter(d.get("phrase", "?") for _, d in rows)
    anchored = sum(1 for _, d in rows if d.get("anchored"))
    sessions = len({d.get("session") for _, d in rows})
    print(f"{len(rows)} relative time references, {sessions} sessions, last {args.days} days")
    print(f"{anchored} of them in a reply that also carried a hard time anchor "
          f"({100.0 * anchored / len(rows):.0f} %)\n")

    print("wording, most frequent first:")
    for phrase, n in phrases.most_common(12):
        print(f"  {n:4d}  {phrase}")

    print("\nsentences (newest last) - check the un-anchored ones first:")
    for when, d in sorted(rows, key=lambda r: r[0]):
        mark = "  " if d.get("anchored") else "!!"
        print(f"{mark} {when.astimezone().strftime('%m-%d %H:%M')} "
              f"[{d.get('phrase', '?')}] {d.get('sentence', '')}")

    print("\n!! = no hard time anchor in that reply. Not an error - the cheap "
          "signal for which sentence to verify first.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
