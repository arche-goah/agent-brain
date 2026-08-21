#!/usr/bin/env python3
"""Fixtures for scripts/transcript-recall.py — hits, no hits, --all, --session, age cut."""
import json
import os
import subprocess
import sys
import tempfile
import time

TOOL = os.path.join(os.path.dirname(__file__), "transcript-recall.py")


def line(role, text, ts="2026-08-20T10:00:00.000Z"):
    return json.dumps({"timestamp": ts, "message": {"role": role, "content": text}})


def tool_line(name, inp):
    return json.dumps({"timestamp": "2026-08-20T10:01:00.000Z", "message": {"role": "assistant",
                       "content": [{"type": "tool_use", "name": name, "id": "t1", "input": inp}]}})


def run(d, *args):
    p = subprocess.run([sys.executable, TOOL, *args, "--dir", d], capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def main():
    ok = True
    with tempfile.TemporaryDirectory() as d:
        a = os.path.join(d, "aaaa-1111.jsonl")
        b = os.path.join(d, "bbbb-2222.jsonl")
        open(a, "w").write("\n".join([line("user", "bitte phaser mechanismus klaeren"),
                                      tool_line("mcp__grandma3__gma3_object_children", {"path": "Phaser 1"}),
                                      line("assistant", "Befund: Phaser laeuft ueber Proxy-Executors")]) + "\n")
        open(b, "w").write("\n".join([line("user", "rig check"), line("assistant", "alles gruen")]) + "\n")
        old = os.path.join(d, "cccc-3333.jsonl")
        open(old, "w").write(line("assistant", "phaser uralt") + "\n")
        os.utime(old, (time.time() - 40 * 86400,) * 2)

        rc, out = run(d, "phaser")
        ok &= rc == 0 and "aaaa-1111" in out and "cccc-3333" not in out and "bbbb-2222" not in out
        print(("ok  " if rc == 0 and "aaaa-1111" in out else "FAIL") + "  keyword hit, old session cut by --days")
        rc, out = run(d, "phaser", "--days", "60")
        ok &= "cccc-3333" in out
        print(("ok  " if "cccc-3333" in out else "FAIL") + "  --days widens the window")
        rc, out = run(d, "nichtdrin")
        ok &= rc == 1
        print(("ok  " if rc == 1 else "FAIL") + "  no hit -> exit 1")
        rc, out = run(d, "phaser", "proxy", "--all")
        ok &= rc == 0 and "aaaa-1111" in out
        print(("ok  " if rc == 0 else "FAIL") + "  --all requires both keywords on one line")
        rc, out = run(d, "gruen", "--session", "aaaa-1111")
        ok &= rc == 1
        print(("ok  " if rc == 1 else "FAIL") + "  --session restricts to one transcript")
        rc, out = run(d, "phaser", "--json")
        ok &= rc == 0 and json.loads(out)["sessions"][0]["session"] == "aaaa-1111"
        print(("ok  " if rc == 0 else "FAIL") + "  --json shape")
        rc, out = run(os.path.join(d, "missing"), "x")
        ok &= rc == 2
        print(("ok  " if rc == 2 else "FAIL") + "  missing dir -> exit 2, says so")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
