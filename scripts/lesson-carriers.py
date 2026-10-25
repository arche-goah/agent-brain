#!/usr/bin/env python3
"""lesson-carriers.py — which lessons in the feedback protocol have no carrier?

WHY (operator, 2026-10-25, after the macOS instance cut a second beta tag on one day although
the rule "one tag per strand, no tag because it is green" had stood since 2026-08-30): "was that
only prose so far? then I ask one level deeper why you never anchored these clear instructions
mechanically." Measured on that brain: 114 protocol entries, 11 with a carrier line — every
operator correction became a sharper rule sentence, almost none a check, a gate, a tool or a
documented mechanism. A prose lesson is recalled as stimulus→response and loses against the
moment (core rule, Knowledge Carriers: lesson → invariant → carrier).

THE INVARIANT: every entry of the feedback protocol names its carrier on a line of its own:
    Traeger: <check/gate/script/skill/doc> — or —  Traeger: Prosa, weil <why no mechanism fits>
(key words per instance: `carrier_keys`). "Prose, because …" is a decision, not a gap; a
missing line is the gap.

WHERE IT RUNS: at session close (skill session-close, next to commitments.py) over the entries
dated in this session, and in the brain-scan over everything since the last scan. A REPORT,
not a gate: it never fires in the middle of a conversation (operator 2026-10-25: "weigh running
stop checks against a check at session close, like the empty-promises check" — the entries are
written one to three times a session and the carrier question needs thought, not a block).

Instance data: `.claude/rules/lesson-carriers.json`
    {"protocol": "docs/maintenance/feedback-protokoll.md",
     "carrier_keys": ["Traeger", "Träger", "Carrier"],
     "entry_heading": "^## (\\d{4}-\\d{2}-\\d{2})"}
Usage: lesson-carriers.py [--repo DIR] [--protocol FILE] [--since YYYY-MM-DD] [--json]
Output: one line per entry without a carrier, then
`lesson-carriers summary: entries=N carried=N loose=N`. Exit 0 always (report).
"""
from __future__ import annotations
import argparse
import json
import os
import re
import sys

DEFAULTS = {
    "protocol": "docs/maintenance/feedback-protokoll.md",
    "carrier_keys": ["Traeger", "Träger", "Carrier"],
    "entry_heading": r"^## (\d{4}-\d{2}-\d{2})",
}


def load_config(repo: str) -> dict:
    cfg = dict(DEFAULTS)
    path = os.path.join(repo, ".claude", "rules", "lesson-carriers.json")
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        for k in DEFAULTS:
            if k in data:
                cfg[k] = data[k]
    except (OSError, ValueError):
        pass
    return cfg


def entries(text: str, heading_rx: str):
    """Yield (date, title, body) per protocol entry whose heading carries a date."""
    rx = re.compile(heading_rx)
    cur = None
    for line in text.splitlines():
        m = rx.match(line)
        if m:
            if cur:
                yield cur
            cur = [m.group(1), line[m.end():].strip(" —-:·"), []]
        elif line.startswith("## ") and cur:
            yield cur
            cur = None
        elif cur is not None:
            cur[2].append(line)
    if cur:
        yield cur


def has_carrier(body: list[str], keys: list[str]) -> bool:
    rx = re.compile(r"^\s*\**(?:%s)\**\s*:" % "|".join(re.escape(k) for k in keys), re.I)
    return any(rx.match(ln) for ln in body)


def main() -> int:
    ap = argparse.ArgumentParser(description="lessons in the feedback protocol without a carrier line")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--protocol")
    ap.add_argument("--since", help="only entries dated on/after YYYY-MM-DD")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    cfg = load_config(a.repo)
    proto = a.protocol or os.path.join(a.repo, cfg["protocol"])
    try:
        with open(proto, encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        print(f"lesson-carriers: cannot read {proto}: {e}")
        print("lesson-carriers summary: entries=0 carried=0 loose=0 (protocol unreadable — NOT checked)")
        return 0
    found, carried, loose = 0, 0, []
    for date, title, body in entries(text, cfg["entry_heading"]):
        if a.since and date < a.since:
            continue
        found += 1
        if has_carrier(body, cfg["carrier_keys"]):
            carried += 1
        else:
            loose.append({"date": date, "title": title})
    if a.json:
        print(json.dumps({"entries": found, "carried": carried, "loose": loose}, ensure_ascii=False, indent=1))
    else:
        for l in loose:
            print(f"lesson without carrier: {l['date']} — {l['title']}")
        print(f"lesson-carriers summary: entries={found} carried={carried} loose={len(loose)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
