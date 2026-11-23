#!/usr/bin/env python3
"""Fixture for scripts/gate-health.py: a gate that timed out in two sessions is named; one session is not (below the
threshold); a gate's decision (a refusal with a reason) and an old transcript are no malfunction; --all lists every
gate. Usage: python3 scripts/gate-health-test.py   (exit 0 = pass)"""
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
fails = 0


def ok(c, label, out=""):
    global fails
    print(("  ok    " if c else "  FAIL  ") + label + ("" if c else f": {out!r}"))
    fails += 0 if c else 1


def result(text):
    return json.dumps({"type": "user", "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "t", "is_error": True, "content": text}]}}) + "\n"


TIMEOUT = 'PreToolUse:Bash hook error: [node "$CLAUDE_PROJECT_DIR/core/helpers/slow-gate.cjs"]: timed out; blocking because onFailure is "block"'
NUMBERED = 'PreToolUse:Bash hook error: [command hook 7]: timed out; blocking because onFailure is "block"'
DECISION = "PreToolUse:Bash hook error: MECHANISM CHECK (agent-brain): a heredoc"

with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    (d / "s1.jsonl").write_text(result(TIMEOUT) + result(DECISION), encoding="utf-8")
    (d / "s2.jsonl").write_text(result(TIMEOUT) + result(NUMBERED), encoding="utf-8")
    old = d / "s0.jsonl"
    old.write_text(result(TIMEOUT) * 5, encoding="utf-8")
    t = time.time() - 30 * 86400
    os.utime(old, (t, t))

    def run(*a):
        return subprocess.run([sys.executable, str(HERE / "gate-health.py"), "--dir", str(d), *a],
                              capture_output=True, text=True, encoding="utf-8").stdout

    out = run()
    ok("slow-gate timed out 2x in 2 session(s)" in out, "a gate that timed out in two sessions is named, with count and sessions", out)
    ok("command hook 7" not in out, "one session is below the threshold", out)
    ok("MECHANISM" not in out, "a gate's decision is no malfunction", out)
    ok("7x" not in out, "a transcript older than the window is not counted", out)
    out = run("--all")
    ok("command hook 7 timed out 1x in 1 session(s)" in out, "--all lists every gate, a numbered hook too", out)
    empty = d / "empty"
    empty.mkdir()
    out = subprocess.run([sys.executable, str(HERE / "gate-health.py"), "--dir", str(empty)],
                         capture_output=True, text=True, encoding="utf-8").stdout
    ok(out == "", "all quiet: silent", out)

print("gate-health-test: all checks passed" if not fails else f"gate-health-test: {fails} FAILURE(S)")
sys.exit(1 if fails else 0)
