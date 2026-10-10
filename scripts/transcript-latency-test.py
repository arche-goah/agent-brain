#!/usr/bin/env python3
"""Fixture tests for scripts/transcript-latency.py on a synthetic transcript.

The numbers are known by construction (two turns of 10 s, one MCP call of 5 s, two Bash
calls of 3 s and 5 s), so every reported value is checked, not just "it printed
something". The negative controls are the records that must NOT start a turn — a meta
record and a tool result arriving mid-turn — and a subagent transcript, which is not an
operator turn at all; each would shift the counts if it were mistaken for one.
"""
import json
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

SCRIPT = str(Path(__file__).resolve().parent / "transcript-latency.py")
T0 = datetime(2026, 1, 15, 12, 0, 0).astimezone()  # local noon: the day is the same everywhere
DAY = "2026-01-15"


def at(s):
    return (T0 + timedelta(seconds=s)).isoformat()


def user(s, text, meta=False):
    r = {"type": "user", "timestamp": at(s), "message": {"role": "user", "content": text}}
    if meta:
        r["isMeta"] = True
    return r


def result(s, tid):
    return {"type": "user", "timestamp": at(s), "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": tid, "content": "ok"}]}}


def asst(s, *blocks):
    return {"type": "assistant", "timestamp": at(s), "message": {"role": "assistant", "content": list(blocks)}}


def use(tid, name):
    return {"type": "tool_use", "id": tid, "name": name, "input": {}}


RECORDS = [
    user(0, "first prompt"),
    asst(2, use("m1", "mcp__srv__probe")),
    result(7, "m1"),
    asst(10, {"type": "text", "text": "done"}),
    user(100, "second prompt"),
    asst(101, use("b1", "Bash"), use("b2", "Bash")),
    result(104, "b1"),
    user(105, "<meta reminder>", meta=True),
    result(106, "b2"),
    asst(110, {"type": "text", "text": "done again"}),
]


def run(d, *args):
    p = subprocess.run([sys.executable, SCRIPT, "--dir", d, *args], capture_output=True,
                       text=True, encoding="utf-8")
    return p.returncode, p.stdout, p.stderr


def check(cond, title, detail=""):
    print(("ok  " if cond else "FAIL") + "  " + title + ("" if cond else f" - {detail}"))
    return cond


if __name__ == "__main__":
    res = []
    with tempfile.TemporaryDirectory() as d:
        with open(Path(d) / "s1.jsonl", "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(json.dumps(r) for r in RECORDS) + "\nnot json\n")
        sub = Path(d) / "s1" / "subagents"
        sub.mkdir(parents=True)
        with open(sub / "agent-1.jsonl", "w", encoding="utf-8", newline="\n") as fh:
            fh.write(json.dumps(user(300, "subagent prompt")) + "\n"
                     + json.dumps(asst(400, use("x1", "Bash"))) + "\n")
        rc, out, err = run(d, "--json")
        rep = json.loads(out) if rc == 0 else {}
        day = rep.get("days", {}).get(DAY, {})
        fam = rep.get("families", {})
        res += [
            check(rc == 0, "exit 0 on a readable directory", err),
            check(day.get("turns") == 2, "two turns (meta record and tool results open none)", day),
            check(day.get("med_s") == 10, "turn duration 10 s", day),
            check(day.get("med_tool_s") == 8 and day.get("med_model_s") == 5,
                  "tool and model time split", day),
            check(day.get("med_tools") == 2, "tool calls per turn", day),
            check(fam.get("srv", {}).get(DAY, {}).get("med_s") == 5,
                  "MCP family named by its server, latency 5 s", fam),
            check(fam.get("Bash", {}).get(DAY, {}).get("n") == 2,
                  "Bash: two calls, subagent call not counted", fam),
            check(list(fam) == ["Bash", "srv"], "default families = most-called first", list(fam)),
        ]
        rc, out, _ = run(d, "--family", "srv")
        res.append(check(rc == 0 and "== srv latency" in out and "== Bash latency" not in out,
                         "--family limits the report", out))
        rc, out, _ = run(d, "--since", "2026-01-16", "--json")
        res.append(check(rc == 0 and json.loads(out)["days"] == {}, "--since filters days", out))
    rc, _, err = run(str(Path(tempfile.gettempdir()) / "no-such-transcripts-dir"))
    res.append(check(rc == 2, "no directory is exit 2", err))
    sys.exit(0 if all(res) else 1)
