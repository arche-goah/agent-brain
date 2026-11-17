#!/usr/bin/env python3
"""Fixture for the short GitHub cache in scripts/open-items.py (run()).
covers: scripts/open-items.py

A counting stand-in for subprocess.run takes the place of gh (in-process, so it runs the same on every OS).
Proves: the same gh call twice inside the TTL reaches GitHub once; --fresh (ttl 0) asks again; an expired entry
asks again; a failed call is never cached; a non-gh command is never cached; no cache file = no cache.
Exit 0 = all pass."""
import importlib.util
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location("open_items", HERE / "open-items.py")
oi = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oi)

calls = []
answer = {"rc": 0}


def fake_run(cmd, **kw):
    calls.append(cmd)
    return subprocess.CompletedProcess(cmd, answer["rc"], stdout=f"out{len(calls)}", stderr="")


oi.subprocess.run = fake_run
fails = 0


def check(name, cond, detail=""):
    global fails
    print(f"  {'ok  ' if cond else 'FAIL'}  {name}" + ("" if cond else f": {detail}"))
    fails += 0 if cond else 1


GH = ["gh", "api", "graphql", "-f", "query=x"]
with tempfile.TemporaryDirectory() as tmp:
    oi.GH_CACHE.update(file=Path(tmp) / "cache.json", ttl=300)
    a, b = oi.run(GH), oi.run(GH)
    check("the same gh call twice inside the TTL reaches GitHub once", len(calls) == 1 and a == b == (0, "out1"),
          f"{len(calls)} calls, {a} {b}")
    oi.GH_CACHE["ttl"] = 0
    oi.run(GH)
    check("--fresh (ttl 0) asks again", len(calls) == 2, f"{len(calls)} calls")
    oi.GH_CACHE["ttl"] = 300
    got = oi.run(GH)
    check("the --fresh answer is what the next run reads", got == (0, "out2") and len(calls) == 2, f"{len(calls)} calls, {got}")
    data = oi.load_json(oi.GH_CACHE["file"], {})
    for v in data.values():
        v["at"] = time.time() - 301
    oi.save_json(oi.GH_CACHE["file"], data)
    oi.run(GH)
    check("an expired entry asks again", len(calls) == 3, f"{len(calls)} calls")
    answer["rc"] = 1
    other = GH + ["-f", "after=2"]
    oi.run(other), oi.run(other)
    check("a failed call is never cached", len(calls) == 5, f"{len(calls)} calls")
    answer["rc"] = 0
    oi.run(["git", "status"]), oi.run(["git", "status"])
    check("a non-gh command is never cached", len(calls) == 7, f"{len(calls)} calls")
    oi.GH_CACHE["file"] = None
    oi.run(GH), oi.run(GH)
    check("without a cache file nothing is cached", len(calls) == 9, f"{len(calls)} calls")

# Windows review 2026-11-17 (#555): a typo in the TTL env (`5m`) ended the whole list in a ValueError. A real child
# process (Popen: subprocess.run is the patched stand-in above), an empty root, no network needed for the parse.
import os
with tempfile.TemporaryDirectory() as empty:
    p = subprocess.Popen([sys.executable, str(HERE / "open-items.py"), "--root", empty],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                         env={**os.environ, "OPEN_ITEMS_GH_CACHE_TTL": "5m"})
    out, err = p.communicate(timeout=60)
    check("a TTL typo falls back to 300 and says so, no ValueError",
          "ValueError" not in err and "not a whole number of seconds" in err, (err or out)[-300:])

print("open-items-gh-cache: all cases pass" if not fails else f"open-items-gh-cache: {fails} FAILURES")
sys.exit(1 if fails else 0)
