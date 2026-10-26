#!/usr/bin/env python3
"""A state written into rule prose drifts: report dated states that expired or disagree with their record.

WHY (coherence registers 2026-10-15 and earlier, finding "state and alpha status stand in rule prose and
drift" — three rounds): rule lines said "alpha until <date>", "parked since <date>", "currently …" while the
record that carries the state (`.claude/rules/local-machinery.json`, the instance's declaration of every
alpha with its `until`) had moved on. A reader of the rule then acted on a state that was no longer true.
The rule of the core: identity is written, state is read (working-rules.md, File Rules) — a rule line names
the record, not its value. This check finds the lines that still carry the value.

A line counts when it holds a STATE word (alpha, parked, …) and an UNTIL word followed by a date
(`until 2026-11-08`). Two findings:
  expired  the date lies before today — the state ended, the line still says it holds;
  drift    the line names a path (or file name) that local-machinery.json declares as an alpha with a
           DIFFERENT `until` — two copies of one state, one of them wrong.
Words are data: built-in English defaults, the instance adds its own language in
`.claude/rules/state-prose.json` {"state_words": [...], "until_words": [...]}. Files read: CLAUDE.md and
every `.claude/rules/*.md` of the instance. Report only; runs in the brain-scan prep.

Usage: state-prose-lint.py [--repo DIR] [--today YYYY-MM-DD]
Output: one line per finding (`state in prose: …`), then `state-prose summary: lines=N expired=N drift=N`.
Exit 0 always (a report, not a gate).
"""
import argparse
import datetime as dt
import json
import re
import sys
from pathlib import Path

STATE = ["alpha", "parked", "paused", "on hold"]
UNTIL = ["until", "till", "expires"]


def load(path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--today", default=dt.date.today().isoformat())
    a = ap.parse_args(argv)
    root = Path(a.repo)
    extra = load(root / ".claude/rules/state-prose.json", {})
    states = STATE + [str(w) for w in extra.get("state_words", [])]
    untils = UNTIL + [str(w) for w in extra.get("until_words", [])]
    state_re = re.compile(r"\b(?:" + "|".join(re.escape(w) for w in states) + r")\b", re.I)
    until_re = re.compile(r"\b(?:" + "|".join(re.escape(w) for w in untils) + r")\s+(\d{4}-\d{2}-\d{2})\b", re.I)
    alphas = (load(root / ".claude/rules/local-machinery.json", {}).get("alpha") or {})
    declared = {k: str((v or {}).get("until", "")) for k, v in alphas.items() if isinstance(v, dict)}

    files = [root / "CLAUDE.md"] + sorted((root / ".claude/rules").glob("*.md"))
    seen = expired = drift = 0
    for f in files:
        try:
            lines = f.read_text(encoding="utf-8").splitlines()
        except OSError:
            continue
        rel = f.relative_to(root).as_posix()
        for n, line in enumerate(lines, 1):
            if not state_re.search(line):
                continue
            dates = until_re.findall(line)
            if not dates:
                continue
            seen += 1
            for d in dates:
                if d < a.today:
                    expired += 1
                    print(f"state in prose: {rel}:{n} says until {d}, which has passed — "
                          "name the record (local-machinery.json id) instead of its date, or update it")
            for key, until in declared.items():
                name = key.rsplit("/", 1)[-1]
                if until and name and name in line and until not in dates:
                    drift += 1
                    print(f"state in prose: {rel}:{n} names {name} with until {', '.join(dates)}, "
                          f"local-machinery.json says {until} — keep one copy (the record)")
    print(f"state-prose summary: lines={seen} expired={expired} drift={drift}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
