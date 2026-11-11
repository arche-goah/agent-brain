#!/usr/bin/env python3
"""Fixture for audit-audit-plan-check.py — both directions.

Green: every heading of the part reports is covered by a row or listed under the no-finding heading.
Red: a row removed, a bad stage, an unknown exit, an ai-does-it row without check, a source that matches
no heading, no plan at all. Usage: python3 scripts/audit-audit-plan-check-test.py (exit 0 = pass)
"""
import os
import sys
import tempfile
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import importlib.util

spec = importlib.util.spec_from_file_location("plan_check", str(Path(HERE) / "audit-audit-plan-check.py"))
pc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pc)

INVENTORY = "# Inventory\n\n## Method\n\nx\n\n## No trigger\n\nroot-cause-review\n\n## Never ran\n\ny\n"
FUNCTION = "# Function\n\n## 1. Return channel\n\n### 1a. Proposals\n\nz\n\n## 2.1 Red fixture\n\nw\n"
ROWS = [
    "| AA-1 | P0 | review without trigger | inventory.md§No trigger | ai-does-it | core PR | package E |",
    "| AA-2 | P2 | never ran, bound to occasion | inventory.md§Never ran | drop | — | — |",
    "| AA-3 | P1 | proposals half built | function.md§1. Return channel; function.md§1a | ai-does-it | core PR | package C |",
    "| AA-4 | P0 | red fixture | function.md§2.1 | ai-does-it | instance | package H |",
]
NONE = "\n## No finding\n\n- inventory.md: Method — method only.\n"


def run(rows, none=NONE, extra=None):
    d = tempfile.mkdtemp()
    for name, body in (("inventory.md", INVENTORY), ("function.md", FUNCTION)):
        with open(Path(d) / name, "w", encoding="utf-8") as fh:
            fh.write(body)
    with open(Path(d) / "synthesis.md", "w", encoding="utf-8") as fh:
        fh.write("# Synthesis\n\n| id | stage | finding | source | exit | owner | check |\n|---|---|---|---|---|---|---|\n")
        fh.write("\n".join(rows) + "\n" + none)
    if extra:
        extra(d)
    misses, _ = pc.check(d)
    return misses


CASES = [
    ("complete plan is green", lambda: run(ROWS), False),
    ("a row removed leaves a heading uncovered", lambda: run(ROWS[:3]), True),
    ("stage outside P0-P2", lambda: run([ROWS[0].replace("| P0 |", "| P5 |")] + ROWS[1:]), True),
    ("unknown exit word", lambda: run([ROWS[0].replace("ai-does-it", "ask-later")] + ROWS[1:]), True),
    ("ai-does-it without a check", lambda: run([ROWS[0].replace("| package E |", "| |")] + ROWS[1:]), True),
    ("source matching no heading", lambda: run([ROWS[0].replace("No trigger", "Nothing like it")] + ROWS[1:]), True),
    ("no plan rows at all", lambda: run([]), True),
    ("method section not listed as no finding", lambda: run(ROWS, none=""), True),
    ("a pre-run note is no part report", lambda: run(ROWS, extra=lambda d: open(Path(d) / "pre-run.md", "w", encoding="utf-8").write("## Anything\n")), False),
]


def main():
    fail = 0
    for name, fn, want_red in CASES:
        red = bool(fn())
        if red == want_red:
            print(f"  OK   {name}")
        else:
            print(f"  FAIL {name}: {'red' if red else 'green'}")
            fail = 1
    print("audit-audit-plan-check fixtures: " + ("FAILURES" if fail else "ALL passed"))
    return fail


if __name__ == "__main__":
    sys.exit(main())
