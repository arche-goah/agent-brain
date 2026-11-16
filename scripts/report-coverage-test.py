#!/usr/bin/env python3
"""covers: report-coverage

The two measured cases (root-cause review 2026-11-16, class A): a net total built from part of the
order blocks, and a summary built from part of the areas. Each is caught; the full report and the
report that names what it left out pass. Negative control: with the check off (every key counted
as covered) the partial report passes - so the cases do test the check.

Run: scripts/report-coverage-test.py    Exit 0 = all green.
"""
from __future__ import annotations

import importlib.util
import io
import contextlib
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("rc", ROOT / "scripts" / "report-coverage.py")
rc = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(rc)

fails = 0


def check(cond, name):
    global fails
    print(f"  {'OK  ' if cond else 'FAIL'} {name}")
    if not cond:
        fails += 1


def run(tmp: Path, source: str, report: str, pattern: str) -> int:
    s, r = tmp / "src.md", tmp / "rep.md"
    s.write_text(source, encoding="utf-8")
    r.write_text(report, encoding="utf-8")
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        return rc.main(["--source", str(s), "--parts", pattern, "--report", str(r)])


ORDERS = "## Block reichelt\n12.40\n## Block alza\n230.00\n## Block proshop\n560.00\n"
AREAS = "- area: event-network\n- area: grandma3\n- area: heavy-metal\n- area: core\n"

with tempfile.TemporaryDirectory() as d:
    t = Path(d)
    block = r"^## Block (\S+)"
    area = r"^- area: (\S+)"
    check(run(t, ORDERS, "Total net 242.40 (reichelt, alza)", block) == 1, "order total from two of three blocks is caught")
    check(run(t, ORDERS, "Total net 802.40 (reichelt, alza, proshop)", block) == 0, "total over all blocks passes")
    check(run(t, ORDERS, "Total net 242.40 (reichelt, alza)\nleft out: proshop (not ordered yet)", block) == 0,
          "a named left-out block passes")
    check(run(t, AREAS, "Summary: event-network and core are on track.", area) == 1, "summary from two of four areas is caught")
    check(run(t, AREAS, "event-network, grandma3, heavy-metal and core: on track.", area) == 0, "summary over all areas passes")
    check(run(t, AREAS, "x", r"^- nothing: (\S+)") == 2, "a pattern that finds no part is a usage error, not a pass")
    real = rc.missing
    rc.missing = lambda keys, report: []
    check(run(t, ORDERS, "Total net 242.40 (reichelt, alza)", block) == 0, "negative control: check off, partial report passes")
    rc.missing = real

print("report-coverage fixtures: " + ("ALL passed" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
