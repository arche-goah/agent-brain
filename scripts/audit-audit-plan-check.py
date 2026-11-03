#!/usr/bin/env python3
"""audit-audit-plan-check.py — does an audit-audit action plan handle every finding?

WHY (operator, 2026-11-02, translated): "it needs an action plan by priority in which every finding is
handled — otherwise the scan is nice but of no real use". A synthesis that summarises is no plan, and a
plan that leaves a report section out loses its findings silently. Built on the macOS instance for its
second audit-audit run (47 rows, green; one row removed: red).

Reads the run folder: every part report (*.md except the synthesis and the pre-run note) and the
synthesis. Red (exit 1) when
  1. the synthesis has no plan rows: table lines whose first cell is an id like AA-1, seven cells in the
     order id | stage | finding | source | exit | owner | check (header words are free, positions count);
  2. a row's stage is not P0/P1/P2, its exit not in the backlog-catch-up vocabulary, a source entry not
     `<report>.md§<heading words>` resolving to a heading of that report, or an ai-does-it /
     operator-decision row has no check;
  3. a ## / ### heading of a part report is named by no row's source and does not stand in the
     no-finding section (a heading starting with --none-heading, default "No finding").

Usage: python3 scripts/audit-audit-plan-check.py <run folder> [--synthesis FILE] [--none-heading TEXT]
       [--skip FILE ...]
"""
import argparse
import os
import re
import sys
from pathlib import Path

EXITS = {"ai-does-it", "done-already", "drop", "in-pr", "later-at-system", "operator-decision", "other-side", "parked"}
STAGES = {"P0", "P1", "P2"}
ROW_ID = re.compile(r"^[A-Z]{1,4}-?\d+$")
SOURCE = re.compile(r"`?([\w.-]+\.md)§(.+?)`?$")


def norm(s):
    return re.sub(r"[^\w]+", " ", s.lower()).strip()


def headings(path):
    out = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r"^(##|###)\s+(.*)", line)
            if m:
                out.append(norm(m.group(2)))
    return out


def plan_rows(text):
    rows = []
    for line in text.splitlines():
        if not line.lstrip().startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 7 and ROW_ID.match(cells[0]):
            rows.append(cells[:7])
    return rows


def none_section(text, heading):
    m = re.search(r"^##\s+" + re.escape(heading) + r".*$", text, re.M | re.I)
    if not m:
        return ""
    rest = text[m.end():]
    nxt = re.search(r"^##\s", rest, re.M)
    return norm(rest[: nxt.start()] if nxt else rest)


def check(folder, synthesis=None, none_heading="No finding", skip=()):
    misses = []
    names = sorted(f for f in os.listdir(folder) if f.endswith(".md"))
    syn = synthesis or next((f for f in ("synthesis.md", "synthese.md") if f in names), None)
    if not syn or not (Path(folder) / syn).exists():
        return ["synthesis missing"], 0
    skipped = {syn, "pre-run.md", "vorab-reflexion.md", *skip}
    heads = {r: headings(Path(folder) / r) for r in names if r not in skipped}
    with open(Path(folder) / syn, encoding="utf-8") as fh:
        text = fh.read()
    rows = plan_rows(text)
    if not rows:
        misses.append("no plan rows (| id | stage | finding | source | exit | owner | check |)")
    covered = set()
    for rid, stage, _finding, source, exit_, _owner, chk in rows:
        if stage not in STAGES:
            misses.append(f"{rid}: stage '{stage}' not P0/P1/P2")
        ex = exit_.split()[0] if exit_ else ""
        if ex not in EXITS:
            misses.append(f"{rid}: exit '{exit_}' not in the backlog-catch-up vocabulary")
        if ex in ("ai-does-it", "operator-decision") and not chk.strip("`— -"):
            misses.append(f"{rid}: exit {ex} without a check")
        for ref in (r for r in re.split(r";\s*", source) if r.strip()):
            m = SOURCE.match(ref.strip())
            if not m:
                misses.append(f"{rid}: source '{ref.strip()}' is not <report>.md§<heading>")
                continue
            rep, want = m.group(1), norm(m.group(2))
            if rep not in heads:
                misses.append(f"{rid}: source report {rep} not in the run folder")
                continue
            hits = [h for h in heads[rep] if want and want in h]
            if not hits:
                misses.append(f"{rid}: source {rep}§{m.group(2)} matches no heading")
            covered.update((rep, h) for h in hits)
    listed = none_section(text, none_heading)
    for rep, hs in heads.items():
        for h in hs:
            if (rep, h) not in covered and not (h and h in listed):
                misses.append(f"uncovered: {rep}§{h}")
    return misses, len(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder")
    ap.add_argument("--synthesis")
    ap.add_argument("--none-heading", default="No finding")
    ap.add_argument("--skip", nargs="*", default=[])
    a = ap.parse_args()
    misses, n = check(a.folder, a.synthesis, a.none_heading, a.skip)
    for m in misses:
        print("MISS", m)
    print(f"audit-audit-plan-check: rows={n} misses={len(misses)}")
    return 1 if misses else 0


if __name__ == "__main__":
    sys.exit(main())
