#!/usr/bin/env python3
"""Fixture for transcript_kind.py: a headless call is recognised by its FIRST entrypoint, also after a long prompt;
a session that quotes the field later stays a session. Usage: python3 scripts/transcript-kind-test.py (exit 0 = pass)"""
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from transcript_kind import is_headless, sessions  # noqa: E402

fails = 0


def check(cond, name):
    global fails
    print(("  OK   " if cond else "  FAIL ") + name)
    fails += 0 if cond else 1


with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    long_prompt = "x" * 20000
    (d / "headless.jsonl").write_text(json.dumps({"type": "user", "message": {"content": long_prompt},
                                                   "entrypoint": "sdk-cli"}) + "\n", encoding="utf-8")
    (d / "session.jsonl").write_text(json.dumps({"type": "user", "entrypoint": "cli", "message": {"content": "go"}}) + "\n"
                                     + json.dumps({"type": "assistant", "message": {"content": 'quoted "entrypoint":"sdk-cli"'}}) + "\n",
                                     encoding="utf-8")
    (d / "empty.jsonl").write_text("", encoding="utf-8")
    check(is_headless(d / "headless.jsonl"), "a headless call is found after a 20 KB prompt")
    check(not is_headless(d / "session.jsonl"), "a session quoting the field later stays a session")
    check(not is_headless(d / "empty.jsonl") and not is_headless(d / "missing.jsonl"), "empty or missing is no headless call")
    got = [p.name for p in sessions(sorted(d.glob("*.jsonl")))]
    check(got == ["empty.jsonl", "session.jsonl"], f"sessions() drops only the headless call ({got})")

print("transcript-kind-test: " + ("all checks passed" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
