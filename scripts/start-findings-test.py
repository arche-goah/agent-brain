#!/usr/bin/env python3
"""Fixture test for scripts/start-findings.py — both directions.

The order (operator 2026-11-12, translated): every session-start finding gets a stable id, an owner and a counter;
the start shows one count line, up to three operator items and the loud ones; nothing is lost. Cases: the id holds
across a changed count/date/sha and differs between findings; one count per session (a resume of the same session
adds none); loud after N; closed when a start no longer prints it, reopened when it returns; "handled" holds within
its session and is cleared when the finding is back at a later start; operator owner by pattern, cap of three; the
body keeps the open-items block and the proof lines; BOOTUP_FULL_FINDINGS=1 keeps every line; a hand run (no
session id) writes no state.
Usage: python3 scripts/start-findings-test.py (exit 0 = pass)
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "start-findings.py"
sys.path.insert(0, str(HERE))
fails = 0


def ok(cond, name):
    global fails
    print(f"  {'OK ' if cond else 'FAIL'} {name}")
    if not cond:
        fails += 1


def run(root, args, body="", env=None):
    e = dict(os.environ)
    e.pop("BOOTUP_FULL_FINDINGS", None)
    e.update(env or {})
    p = subprocess.run([sys.executable, str(SCRIPT), "--root", str(root), *args], input=body,
                       capture_output=True, text=True, encoding="utf-8", env=e)
    return p.returncode, p.stdout


# one local date per session id: s1 and s1b share a day, the others each get their own
DAYS = {"s1": "2026-11-01", "s1b": "2026-11-01", "s2": "2026-11-02", "s3": "2026-11-03", "s4": "2026-11-04",
        "s5": "2026-11-05", "s6": "2026-11-06", "s7": "2026-11-07", "s8": "2026-11-08"}


def record(root, session, body, env=None):
    hi = json.dumps({"session_id": session}) if session else ""
    e = {"START_FINDINGS_TODAY": DAYS.get(session, "2026-11-01")}
    e.update(env or {})
    return run(root, ["record", "--hook-input", hi], body, e)[1]


def state(root):
    p = root / ".claude-state" / "start-findings.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else None


import importlib.util  # noqa: E402

spec = importlib.util.spec_from_file_location("sf", SCRIPT)
sf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sf)

# 1 stable id
a = sf.fid("!! hook coverage: 3 rules missing since 2026-11-01 (pin 1a2b3c4d)")
b = sf.fid("!! hook coverage: 12 rules missing since 2026-11-10 (pin 9f8e7d6c)")
c = sf.fid("!! broken skill symlinks: foo")
ok(a == b, "same finding keeps its id across a changed count, date and sha")
ok(a != c, "a different finding gets a different id")
ok(sf.fid("!! skills added to the table") == sf.fid("!! skills added to the table"), "a hex-looking word without a digit stays text")
# a line that ends in a list is keyed by its head: the list may change, the finding stays one
ok(sf.fid("!! ledger: 2 open entries without a check line: a, b") == sf.fid("!! ledger: 2 open entries without a check line: a, c"),
   "a list after the last ': ' that changed keeps the id")
ok(sf.fid("!! PR waiting on you: x | y") == sf.fid("!! PR waiting on you: z"), "a ' | ' list and a single item keep the id")
ok(sf.fid("!! ledger: 24 check(s) refused, not run: a, b") != sf.fid("!! ledger: 2 open entries without a check line: a, b"),
   "two different heads stay two ids")
ok(sf.fid("!! hook coverage: 3 rules missing — fill it") != sf.fid("!! hook coverage: 3 tools missing — fill it"),
   "a tail that is prose, not a list, still counts in the id")

AI1 = "!! hook coverage: 3 rules missing — fill the data file"
OP1 = "!! update available: v2.1.6 — ask the operator, then run brain-update.sh"
BLOCK = "open for us: 0 — ai 0 · human 0 · unclassified 0\n- nothing open (requests, PRs and work ledgers read)"
PROOF = "!! session start took 25 s of its 30 s limit — slowest: x 9 s"


def body(*lines):
    return "git: clean\n" + "\n".join(lines) + "\n" + BLOCK + "\n=== END BOOTUP ==="


with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    (root / ".claude" / "rules").mkdir(parents=True)
    (root / ".claude" / "rules" / "start-findings.json").write_text(json.dumps({"loud_after_days": 3}), encoding="utf-8")

    # 8 hand run: no state
    out = record(root, "", body(AI1))
    ok(state(root) is None, "a hand run (no session id) writes no state")
    ok(out == body(AI1), "a hand run prints every line unchanged")

    out = record(root, "s1", body(AI1 + "\n    detail line", OP1))
    st = state(root)
    k_ai, k_op = sf.fid(AI1), sf.fid(OP1)
    ok(st["findings"][k_ai]["sessions_seen"] == 1, "first start counts 1")
    ok(st["findings"][k_ai]["owner"] == "ai" and st["findings"][k_op]["owner"] == "operator", "owner: ai by default, operator by pattern")
    ok(st["findings"][k_ai]["detail"] == ["detail line"], "the indented sub-line is kept as detail")
    ok("!! session-start findings: 2 " in out, "the brief count line is printed")
    ok(f"[finding|operator] {k_op}" in out, "the operator item is shown")
    ok(AI1 not in out and "detail line" not in out, "an ai finding below the loud mark leaves the body (tracked)")
    ok(BLOCK in out and "=== END BOOTUP ===" in out and "git: clean" in out, "every other line of the body stays")

    record(root, "s1", body(AI1.replace("3", "4"), OP1))
    ok(state(root)["findings"][k_ai]["sessions_seen"] == 1, "a resume of the same session counts nothing")

    rc, _ = run(root, ["handled", k_ai, "--how", "filled the data file"])
    ok(rc == 0 and state(root)["findings"][k_ai].get("handled_at"), "handled marks the entry")
    record(root, "s1", body(AI1, OP1))
    ok(state(root)["findings"][k_ai].get("handled_at"), "handled holds within its own session")
    rc, _ = run(root, ["handled", "deadbeef", "--how", "x"])
    ok(rc == 1, "an unknown id is refused")

    out = record(root, "s1b", body(AI1, OP1))
    e = state(root)["findings"][k_ai]
    ok(e["sessions_seen"] == 2 and e["days_seen"] == 1, "a second session on the same day counts a session, not a day")
    ok(not e.get("handled_at") and e.get("reopened") == 1, "handled but back at a later start: reopened, handled cleared")

    out = record(root, "s2", body(AI1, OP1))
    e = state(root)["findings"][k_ai]
    ok(e["sessions_seen"] == 3 and e["days_seen"] == 2, "a new day counts a day")
    ok("[finding|loud]" not in out, "two days are below the loud mark (data: 3 days)")

    out = record(root, "s3", body(AI1, OP1, PROOF))
    ok(f"[finding|loud] {k_ai} seen on 3 days (4 sessions), not handled:" in out, "loud after N (data: 3) days")
    ok(f"[finding|operator+loud] {k_op}" in out, "an operator item that is loud carries both tags")
    ok(PROOF in out, "the proof line session-audit reads stays verbatim")
    ok("!! session-start findings: 3 " in out, "the proof line is counted too")

    out = record(root, "s4", body(OP1))
    e = state(root)["findings"][k_ai]
    ok(e.get("closed_at"), "a finding the start no longer prints is closed")
    ok(k_ai not in out, "a closed finding is not in the brief")
    record(root, "s5", body(AI1, OP1))
    e = state(root)["findings"][k_ai]
    ok(not e.get("closed_at") and e["sessions_seen"] == 5 and e["days_seen"] == 4, "a closed finding that returns is reopened and counts on")

    out = record(root, "s6", body(AI1, OP1), env={"BOOTUP_FULL_FINDINGS": "1"})
    ok(AI1 in out and "session-start findings:" not in out, "BOOTUP_FULL_FINDINGS=1 keeps every line")
    _, lst = run(root, ["list"])
    ok(AI1[3:] in lst and k_op in lst, "list prints every open finding in full")

    ops = [f"!! check {n}: something — ask the operator" for n in ("alpha", "beta", "gamma", "delta", "epsilon")]
    out = record(root, "s7", body(*ops))
    ok(out.count("[finding|operator] ") == 4 and "2 more need the operator" in out, "at most three operator items, the rest offered")

    out = record(root, "s8", "git: clean\n" + BLOCK + "\n=== END BOOTUP ===")
    ok("session-start findings" not in out, "no finding: no brief line (a clean check is silence)")

with tempfile.TemporaryDirectory() as td:
    # the brief subcommand and --brief agree
    root = Path(td)
    record(root, "x1", body(OP1))
    _, b1 = run(root, ["brief"])
    _, b2 = run(root, ["--brief"])
    ok(b1 == b2 and "session-start findings: 1" in b1, "--brief prints the brief view of the state")

print("start-findings: all cases pass" if not fails else f"start-findings: {fails} FAILURES")
sys.exit(1 if fails else 0)
