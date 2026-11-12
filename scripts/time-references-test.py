#!/usr/bin/env python3
"""Fixtures for time-references.py, both directions.

  1. no log at all -> "no record yet", exit 0, never a crash
  2. entries in the window -> counted, un-anchored ones marked `!!`, rotated half included
  3. an entry outside the window -> not counted
  4. --unanchored and --phrase filter; a window with nothing -> "nothing recorded"

Usage: python3 scripts/time-references-test.py   (exit 0 = all fixtures pass)
"""
import datetime
import json
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    sys.stderr.reconfigure(encoding="utf-8")
except (AttributeError, ValueError):
    pass

TOOL = Path(__file__).resolve().parent / "time-references.py"
fails = []


def ok(n, cond, detail=""):
    print(f"  {'ok  ' if cond else 'FAIL'}  {n}{'' if cond else ': ' + detail}")
    if not cond:
        fails.append(n)


def run(root, *args):
    p = subprocess.run([sys.executable, str(TOOL), "--root", str(root), *args],
                       capture_output=True, text=True, encoding="utf-8")
    return p.returncode, p.stdout + p.stderr


now = datetime.datetime.now(datetime.timezone.utc)
iso = lambda d: (now - datetime.timedelta(days=d)).isoformat().replace("+00:00", "Z")

print("time-references")
with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    rc, out = run(root)
    ok("no log: says so, exit 0", rc == 0 and "no record yet" in out, out)

    st = root / ".claude-state"
    st.mkdir()
    rows = [
        {"at": iso(1), "session": "s1", "phrase": "yesterday", "sentence": "It was yesterday.", "anchored": False},
        {"at": iso(1), "session": "s1", "phrase": "recently", "sentence": "Fixed recently, 2026-01-02.", "anchored": True},
        {"at": iso(30), "session": "s0", "phrase": "last week", "sentence": "Old one.", "anchored": False},
    ]
    (st / "time-gate.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows[:2]), encoding="utf-8")
    (st / "time-gate.1.jsonl").write_text(json.dumps(rows[2]) + "\n" + json.dumps(
        {"at": iso(2), "session": "s2", "phrase": "yesterday", "sentence": "Rotated half.", "anchored": False}) + "\n",
        encoding="utf-8")

    rc, out = run(root)
    ok("window: three entries in 7 days (rotated half included, old one out)",
       rc == 0 and out.startswith("3 relative time references, 2 sessions"), out[:200])
    ok("un-anchored sentence is marked !!", "!! " in out and "[yesterday] It was yesterday." in out, out)
    ok("anchored sentence is not marked", "   " in out and "[recently] Fixed recently" in out
       and "!! " not in out.split("[recently]")[0].splitlines()[-1], out)
    ok("old entry outside the window is not listed", "Old one." not in out, out)
    rc, out = run(root, "--unanchored")
    ok("--unanchored drops the anchored reply", "Fixed recently" not in out and "It was yesterday." in out, out)
    rc, out = run(root, "--phrase", "recently")
    ok("--phrase filters the wording", out.startswith("1 relative time references"), out[:120])
    rc, out = run(root, "--phrase", "tonight")
    ok("a filter with no hit says nothing recorded", rc == 0 and "nothing recorded" in out, out)

print()
print("time-references fixtures: " + ("ALL passed" if not fails else f"{len(fails)} FAILED"))
sys.exit(1 if fails else 0)
