#!/usr/bin/env python3
"""Fixtures for memory-usage.py — both directions.

  1. a Read of a memory file counts as an open; a Write/Edit does NOT
  2. a Bash reader (cat/sed) on a memory path counts; a Bash writer (echo >) does not
  3. a file no transcript opened is listed under never_opened; MEMORY.md never is
  4. precision joins the hook log with the transcripts: named+opened / named-only /
     opened-only; a record whose session has no transcript is not judged
  5. a transcript directory that does not exist -> exit 2, no traceback
Paths are built with pathlib and compared as posix text (OS-1).
"""
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("memory_usage", HERE / "memory-usage.py")
mu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mu)

fail = 0


def ok(msg):
    print(f"  OK  {msg}")


def bad(msg):
    global fail
    fail = 1
    print(f"  FAIL {msg}")


def tool_line(name, **inp):
    return json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": "x", "name": name, "input": inp}]}})


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    tdir = root / "transcripts"
    mem = root / "memory"
    tdir.mkdir()
    mem.mkdir()
    for f in ("MEMORY.md", "read-me.md", "bash-me.md", "written-only.md", "orphan.md"):
        (mem / f).write_text("---\nname: x\ndescription: y\n---\n", encoding="utf-8")
    memp = mem.as_posix()
    (tdir / "s1.jsonl").write_text("\n".join([
        tool_line("Read", file_path=f"{memp}/read-me.md"),
        tool_line("Write", file_path=f"{memp}/written-only.md", content="x"),
        tool_line("Bash", command=f"sed -n 1,20p {memp}/bash-me.md"),
        tool_line("Bash", command=f"echo hi > {memp}/orphan.md"),
        tool_line("Read", file_path=f"{memp}/MEMORY.md"),
    ]) + "\n", encoding="utf-8")
    (tdir / "s2.jsonl").write_text(tool_line("Read", file_path=f"{memp}/read-me.md") + "\n", encoding="utf-8")

    per = mu.scan(tdir)
    rep = mu.usage_report(per, tdir, mem)
    by = {r["file"]: r for r in rep["per_file"]}
    # 1
    if by["read-me.md"]["opens"] == 2 and by["read-me.md"]["sessions"] == 2:
        ok("1 Read counts (2 opens, 2 sessions)")
    else:
        bad(f"1 read-me: {by['read-me.md']}")
    if by["written-only.md"]["opens"] == 0:
        ok("1 Write is not an open")
    else:
        bad("1 Write counted as open")
    # 2
    if by["bash-me.md"]["opens"] == 1:
        ok("2 Bash sed counts")
    else:
        bad(f"2 bash-me: {by['bash-me.md']}")
    if by["orphan.md"]["opens"] == 0:
        ok("2 Bash echo-redirect is not an open")
    else:
        bad("2 Bash writer counted")
    # 3
    never = set(rep["never_opened"])
    if never == {"written-only.md", "orphan.md"}:
        ok("3 never_opened lists exactly the unopened files, MEMORY.md excluded")
    else:
        bad(f"3 never_opened: {sorted(never)}")
    # 4
    state = root / "memory-recall.jsonl"
    state.write_text("\n".join([
        json.dumps({"session": "s1", "files": [{"file": "read-me.md"}, {"file": "orphan.md"}], "topics": []}),
        json.dumps({"session": "s2", "files": [], "topics": [{"file": "index-x.md"}]}),
        json.dumps({"session": "ghost", "files": [{"file": "read-me.md"}], "topics": []}),
    ]) + "\n", encoding="utf-8")
    p = mu.precision_report(per, state)
    # s1: named {read-me, orphan}, opened {read-me, bash-me, MEMORY.md} -> tp 1, fp 1, fn 1 (bash-me)
    # s2: named {index-x}, opened {read-me} -> tp 0, fp 1, fn 1
    exp = {"records": 3, "sessions_judged": 2, "named_and_opened": 1, "named_not_opened": 2, "opened_not_named": 2}
    got = {k: p[k] for k in exp}
    if got == exp and p["precision"] == round(1 / 3, 3) and p["recall"] == round(1 / 3, 3):
        ok("4 precision/recall joined correctly, ghost session skipped")
    else:
        bad(f"4 precision: {p}")
    # 5
    rc = mu.main(["--dir", (root / "nope").as_posix()])
    if rc == 2:
        ok("5 missing transcript dir -> exit 2")
    else:
        bad(f"5 rc {rc}")

print("memory-usage-test: all green" if fail == 0 else "memory-usage-test: FAILURES")
sys.exit(fail)
