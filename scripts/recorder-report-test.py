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


def line_in(out, label):
    return next((l for l in out.splitlines() if label in l), "")


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
    (st / "own-log.1.jsonl").write_text(jl([{"ts": "2026-10-19T10:00:00Z", "would_block": False}]), encoding="utf-8")
    (st / "own-log.jsonl").write_text(jl([{"ts": "2026-10-22T10:00:00Z", "would_block": False}]), encoding="utf-8")
    # 2026-11-02 (promise shape): the gate's own log AND the dispatcher's marker log both exist; the blocks
    # stand only in the marker log — read both, never one instead of the other.
    (st / "own-gate.jsonl").write_text(jl([{"at": "2026-10-22T11:00:00Z", "session": "c", "would_block": True}]),
                                       encoding="utf-8")
    # 2026-11-02 (time-gate shape): entries without a would_block field — no countable zero.
    (root / ".claude/rules/stop-checks.json").write_text(json.dumps({"checks": json.loads(
        (root / ".claude/rules/stop-checks.json").read_text(encoding="utf-8"))["checks"] + [
        {"label": "NOFIELD", "marker": "NOFIELD-GATE", "cmd": "core/helpers/nofield.cjs", "mode": "record"},
        {"label": "PURELOG", "marker": "PURELOG", "cmd": "core/helpers/purelog.cjs", "mode": "record",
         "counts_blocks": False}]}),
        encoding="utf-8")
    (st / "nofield-gate.jsonl").write_text(jl([{"at": "2026-10-22T10:00:00Z", "session": "a", "anchored": False}]),
                                           encoding="utf-8")
    # a pure log (mode-log shape) declares counts_blocks:false — a plain line, no decision due
    (st / "purelog.jsonl").write_text(jl([{"at": "2026-10-22T10:00:00Z", "session": "a", "mode": "interactive"}]),
                                      encoding="utf-8")
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
    ok("a gate's own log AND the marker log are read, rotated half included",
       "own-log.jsonl" in line("OWN") and "own-gate.jsonl" in line("OWN") and "3 entries" in line("OWN")
       and "1 would have blocked" in line("OWN") and line("OWN").startswith("!! "), line("OWN"))
    ok("a log without a would_block field is not a zero",
       line("NOFIELD").startswith("!! ") and "NOT countable" in line("NOFIELD")
       and "would have blocked" not in line("NOFIELD"), line("NOFIELD"))
    ok("a pure log with counts_blocks:false is no decision",
       not line("PURELOG").startswith("!!") and "blocks nothing by design" in line("PURELOG"), line("PURELOG"))
    ok("a log that never came into being says so", "no log yet" in line("NEVER:"), line("NEVER:"))
    ok("a blocking check is no recorder", "BLOCKER" not in out, out)
    ok("summary counts recorders and due ones",
       "recorder report summary: 6 recorder(s), 3 with a decision due" in out, str(out.splitlines()[-1:]))

    # 2026-11-10 (Windows instance): the template's required recorders run without a line in the instance
    # file — the report counts them too; one the instance switches off with a reason stays out.
    (root / "core/templates/rules-instance").mkdir(parents=True)
    (root / "core/templates/rules-instance/stop-checks.json").write_text(json.dumps({"checks": [
        {"label": "REQ", "marker": "REQ-GATE", "cmd": "core/helpers/req.cjs", "mode": "record", "required": True},
        {"label": "OFF", "marker": "OFF-GATE", "cmd": "core/helpers/off.cjs", "mode": "record", "required": True},
        {"label": "OPT", "marker": "OPT-GATE", "cmd": "core/helpers/opt.cjs", "mode": "record"}]}), encoding="utf-8")
    cfg = json.loads((root / ".claude/rules/stop-checks.json").read_text(encoding="utf-8"))
    cfg["disabled"] = {"OFF-GATE": "switched off on purpose"}
    (root / ".claude/rules/stop-checks.json").write_text(json.dumps(cfg), encoding="utf-8")
    (st / "req-gate.jsonl").write_text(jl([{"at": "2026-10-22T10:00:00Z", "session": "a", "would_block": True}]),
                                       encoding="utf-8")
    out = subprocess.run([sys.executable, str(REPORT), "--root", str(root), "--days", "14",
                          "--today", "2026-10-23"], capture_output=True, text=True, encoding="utf-8").stdout
    ok("a required template recorder is counted", line_in(out, "REQ:").startswith("!! "), line_in(out, "REQ:"))
    ok("a required recorder disabled with a reason and an optional one stay out",
       "OFF" not in out and "OPT" not in out, out)

if fails:
    print(f"recorder-report-test: {len(fails)} FAILURE(S)")
    sys.exit(1)
print("recorder-report-test: all 11 fixtures passed")
