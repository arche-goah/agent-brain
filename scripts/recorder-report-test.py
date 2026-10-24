#!/usr/bin/env python3
"""Fixtures for recorder-report.py, both directions.

  1. a would-block entry inside the window -> `!!` line, decision due
  2. entries outside the window or not blocking -> plain line, nothing due
  3. a gate with its own log (promise-gate shape) -> that log is counted, rotated half included
  4. a recorder whose log never came into being -> "no log yet", never a crash

Usage: python3 scripts/recorder-report-test.py   (exit 0 = all fixtures pass)
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass

REPORT = Path(__file__).resolve().parent / "recorder-report.py"
fails = []


def ok(n, cond, detail=""):
    print(f"  {'ok  ' if cond else 'FAIL'}  {n}{'' if cond else ': ' + detail}")
    if not cond:
        fails.append(n)


def jl(rows):
    return "".join(json.dumps(r) + "\n" for r in rows)


print("recorder-report")
with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    (root / ".claude/rules").mkdir(parents=True)
    (root / ".claude-state").mkdir()
    (root / "core/helpers").mkdir(parents=True)
    (root / "core/helpers/own.cjs").write_text("path.join(dir, 'own-log.jsonl')\n", encoding="utf-8")
    (root / ".claude/rules/stop-checks.json").write_text(json.dumps({"checks": [
        {"label": "DUE", "marker": "DUE-GATE", "cmd": "core/helpers/due.cjs", "mode": "record"},
        {"label": "CALM", "marker": "CALM-GATE", "cmd": "core/helpers/calm.cjs", "mode": "record"},
        {"label": "OWN", "marker": "OWN-GATE", "cmd": "core/helpers/own.cjs", "mode": "record"},
        {"label": "NEVER", "marker": "NEVER-GATE", "cmd": "core/helpers/never.cjs", "mode": "record"},
        {"label": "BLOCKER", "marker": "B-GATE", "cmd": "core/helpers/b.cjs", "mode": "block"},
    ]}), encoding="utf-8")
    st = root / ".claude-state"
    (st / "due-gate.jsonl").write_text(jl([
        {"at": "2026-10-20T10:00:00Z", "session": "a", "would_block": True},
        {"at": "2026-10-21T10:00:00Z", "session": "b", "would_block": False}]), encoding="utf-8")
    (st / "calm-gate.jsonl").write_text(jl([
        {"at": "2026-09-01T10:00:00Z", "session": "a", "would_block": True},
        {"at": "2026-10-21T10:00:00Z", "session": "a", "would_block": False}]), encoding="utf-8")
    (st / "own-log.1.jsonl").write_text(jl([{"ts": "2026-10-19T10:00:00Z"}]), encoding="utf-8")
    (st / "own-log.jsonl").write_text(jl([{"ts": "2026-10-22T10:00:00Z"}]), encoding="utf-8")
    res = subprocess.run([sys.executable, str(REPORT), "--root", str(root), "--days", "14",
                          "--today", "2026-10-23"], capture_output=True, text=True, encoding="utf-8")
    out = res.stdout
    line = lambda label: next((l for l in out.splitlines() if f"{label}" in l), "")  # noqa: E731
    ok("exit 0", res.returncode == 0, res.stderr.strip()[:200])
    ok("a would-block entry in the window is a decision due",
       line("DUE:").startswith("!! ") and "2 entries" in line("DUE:") and "1 would have blocked" in line("DUE:"),
       line("DUE:"))
    ok("an entry outside the window is not counted, nothing due",
       not line("CALM:").startswith("!!") and "1 entry" in line("CALM:") and "0 would have blocked" in line("CALM:"),
       line("CALM:"))
    ok("a gate's own log is read, rotated half included",
       "own log own-log.jsonl" in line("OWN") and "2 entries" in line("OWN"), line("OWN"))
    ok("a log that never came into being says so", "no log yet" in line("NEVER:"), line("NEVER:"))
    ok("a blocking check is no recorder", "BLOCKER" not in out, out)
    ok("summary counts recorders and due ones",
       "recorder report summary: 4 recorder(s), 1 with a decision due" in out, out.splitlines()[-1:])

if fails:
    print(f"recorder-report-test: {len(fails)} FAILURE(S)")
    sys.exit(1)
print("recorder-report-test: all 7 fixtures passed")
