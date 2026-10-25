#!/usr/bin/env python3
"""covers: lesson-carriers
Both directions on a synthetic protocol: an entry with a `Traeger:` line is carried, one with
`Carrier:` too, one with "Traeger: Prosa, weil …" is carried (a decision, not a gap), an entry
without the line is loose and named with date and title, --since drops older entries, a heading
without a date is no entry, an unreadable protocol is said and exits 0, instance data renames
the key. Negative control: with the carrier keys emptied every entry turns loose.
Run: scripts/lesson-carriers-test.py    Exit 0 = all green.
"""
from __future__ import annotations
import importlib.util
import io
import contextlib
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("lc", ROOT / "scripts" / "lesson-carriers.py")
lc = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lc)
fails = 0


def check(cond, name):
    global fails
    print(f"  {'ok  ' if cond else 'FAIL'}  {name}")
    fails += 0 if cond else 1


def run(repo: Path, *args):
    out = io.StringIO()
    sys.argv = ["lesson-carriers.py", "--repo", str(repo), *args]
    with contextlib.redirect_stdout(out):
        rc = lc.main()
    return rc, out.getvalue()


PROTO = """# Feedback-Protokoll

## Ereignis-Regeln (chronologisch)

## 2026-10-01 — Erste Lehre mit Check
Anlass: etwas.
Traeger: core/scripts/foo.py (Check 3).

## 2026-10-02 — Zweite Lehre, englischer Schluessel
Carrier: helpers/bar-gate.cjs

## 2026-10-03 — Dritte Lehre, bewusst Prosa
Regel: nur so.
Traeger: Prosa, weil es eine Geschmacksfrage des Operators ist.

## 2026-10-04 — Vierte Lehre ohne Traeger
Regel: irgendwas.
Reichweite: nur dieses Brain.

## 2026-10-05 — Fuenfte Lehre, fett markiert
**Traeger:** Memory `x` + Gate.
"""

with tempfile.TemporaryDirectory() as d:
    repo = Path(d)
    (repo / "docs" / "maintenance").mkdir(parents=True)
    (repo / "docs" / "maintenance" / "feedback-protokoll.md").write_text(PROTO, encoding="utf-8")

    rc, out = run(repo)
    check(rc == 0, "exit 0 (a report)")
    check("summary: entries=5 carried=4 loose=1" in out, f"four carried, one loose: {out.strip().splitlines()[-1]}")
    check("lesson without carrier: 2026-10-04 — Vierte Lehre ohne Traeger" in out, "the loose entry is named with date and title")
    check("2026-10-03" not in out, "'Prosa, weil' counts as a carrier (a decision, not a gap)")
    check("2026-10-05" not in out, "a bold **Traeger:** line counts")

    rc, out = run(repo, "--since", "2026-10-05")
    check("entries=1 carried=1 loose=0" in out, "--since drops older entries")

    rc, out = run(repo, "--json")
    data = json.loads(out)
    check(data["loose"] == [{"date": "2026-10-04", "title": "Vierte Lehre ohne Traeger"}], "--json lists the loose entry")

    # a heading without a date (the section header) is no entry
    check(data["entries"] == 5, "the dateless section heading is not an entry")

    # instance data renames the key: 'Mechanik' only -> the Traeger/Carrier entries turn loose
    (repo / ".claude" / "rules").mkdir(parents=True)
    (repo / ".claude" / "rules" / "lesson-carriers.json").write_text(json.dumps({"carrier_keys": ["Mechanik"]}), encoding="utf-8")
    rc, out = run(repo)
    check("entries=5 carried=0 loose=5" in out, "negative control: with another key word every entry is loose")
    (repo / ".claude" / "rules" / "lesson-carriers.json").unlink()

    # unreadable protocol: said, exit 0
    rc, out = run(repo, "--protocol", str(repo / "nope.md"))
    check(rc == 0 and "NOT checked" in out, "an unreadable protocol is said, never read as clean")

print("lesson-carriers-test: " + ("all checks passed" if fails == 0 else f"{fails} check(s) FAILED"))
sys.exit(1 if fails else 0)
