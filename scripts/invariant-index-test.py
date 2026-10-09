#!/usr/bin/env python3
"""covers: invariant-index

Both directions: every block gets exactly one line with its own carrier class (a register
entry held by nothing must read `prose`, never borrow a neighbour's `pattern`), the status is
cut but never rephrased, and --write produces LF bytes on every platform.

Run: scripts/invariant-index-test.py    Exit 0 = all green.
"""
from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("ii", ROOT / "scripts" / "invariant-index.py")
ii = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ii)

fails = 0


def check(cond, name):
    global fails
    print(f"  {'ok  ' if cond else 'FAIL'}  {name}")
    fails += 0 if cond else 1


REGISTER = """root: .

## A-1 — searched class
invariant: x
pattern:   foo
status:    closed

## A-2 — tool class
invariant: y
mechanizable: tool — the probe
status:    open

## A-3 — judgement class
mechanizable: no — the word changes every time
status:    offen

## A-4 — prose only
invariant: z
status:    %s
""" % ("closed, and a very long status sentence that goes on " * 4).strip()

with tempfile.TemporaryDirectory() as d:
    reg = Path(d) / "inv.md"
    reg.write_text(REGISTER, encoding="utf-8", newline="\n")
    text = ii.build(reg)
    lines = [ln for ln in text.splitlines() if ln.startswith("- **")]
    check(len(lines) == 4, "one line per block")
    check(lines[0].endswith("· pattern") and "A-1" in lines[0], "pattern carrier")
    check(lines[1].endswith("· tool"), "tool carrier")
    check(lines[2].endswith("· no"), "judgement carrier")
    check(lines[3].endswith("· prose"), "prose entry never borrows a carrier")
    check("…" in lines[3] and len(lines[3]) < 160, "long status cut, not dropped")
    check("offen" in lines[2], "status kept verbatim")
    ii.main([str(reg), "--write"])
    raw = (Path(d) / "inv-index.md").read_bytes()
    check(b"\r\n" not in raw and raw.endswith(b"\n"), "written with LF")
    check(raw.decode("utf-8") == text, "write equals build")

print("invariant-index-test: " + ("all checks passed" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
