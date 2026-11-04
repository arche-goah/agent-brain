#!/usr/bin/env python3
"""Fixtures for memory-usage.py — both directions.

  1. a Read of a memory file counts as an open; a Write/Edit does NOT
  2. a Bash reader (cat/sed) on a memory path counts; a Bash writer (echo >) does not
  3. a file no transcript opened is listed under never_opened; MEMORY.md never is
  4. precision joins the hook log with the transcripts: named+opened / named-only /
     opened-only; a record whose session has no transcript is not judged
  5. a transcript directory that does not exist -> exit 2, no traceback
  6. --usage: a shown topic index counts as followed only when the index or a linked file is read AFTER
     the showing in the same session; a read before it, or the triggering command itself, does not
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
        # a sibling repo whose NAME ends in "memory" is not the memory dir (measured 2026-09-30:
        # brain-shared-memory/README.md and PEOPLE.md were 17 of 56 "opened, not named")
        tool_line("Read", file_path=f"{root.as_posix()}/brain-shared-memory/README.md"),
        tool_line("Bash", command=f"cat {root.as_posix()}/brain-shared-memory/PEOPLE.md"),
    ]) + "\n", encoding="utf-8")
    (tdir / "s2.jsonl").write_text(tool_line("Read", file_path=f"{memp}/read-me.md") + "\n", encoding="utf-8")

    per = mu.scan(tdir)
    if not {"README.md", "PEOPLE.md"} & set(per["s1"]):
        ok("0 a *-memory/ sibling repo is not the memory dir")
    else:
        bad(f"0 foreign repo counted: {dict(per['s1'])}")
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
    # s2: a topic index only -> NOT a pointer, not judged as named; opened {read-me} -> fn 1
    #     (an injected index is never opened; "opened" cannot judge it — replay --truth does)
    exp = {"records": 3, "sessions_judged": 2, "topics_named": 1,
           "named_and_opened": 1, "named_not_opened": 1, "opened_not_named": 2}
    got = {k: p[k] for k in exp}
    if got == exp and p["precision"] == round(1 / 2, 3) and p["recall"] == round(1 / 3, 3):
        ok("4 precision/recall over pointers only, topic counted apart, ghost session skipped")
    else:
        bad(f"4 precision: {p}")
    # 6 --usage (fourth measurement 2026-11-04)
    def ts_line(stamp, name, **inp):
        return json.dumps({"type": "assistant", "timestamp": stamp, "message": {"role": "assistant", "content": [
            {"type": "tool_use", "id": "x", "name": name, "input": inp}]}})
    (mem / "index-x.md").write_text("---\nname: index-x\ndescription: y\n---\n- [a](read-me.md)\n", encoding="utf-8")
    (tdir / "u1.jsonl").write_text("\n".join([
        ts_line("2026-11-04T10:00:00.000Z", "Bash", command=f"cat docs/event-network/offene-punkte.md"),   # the trigger
        ts_line("2026-11-04T10:05:00.000Z", "Read", file_path=f"{memp}/index-x.md"),                        # after: used
    ]) + "\n", encoding="utf-8")
    (tdir / "u2.jsonl").write_text("\n".join([
        ts_line("2026-11-04T09:00:00.000Z", "Read", file_path=f"{memp}/read-me.md"),                        # before: not
        ts_line("2026-11-04T10:00:00.000Z", "Bash", command=f"cat docs/event-network/offene-punkte.md"),
    ]) + "\n", encoding="utf-8")
    (tdir / "u3.jsonl").write_text("\n".join([
        ts_line("2026-11-04T10:00:00.000Z", "Bash", command=f"cat docs/event-network/offene-punkte.md"),
        ts_line("2026-11-04T10:02:00.000Z", "Bash", command=f"sed -n 1,5p {memp}/read-me.md"),              # linked: used
    ]) + "\n", encoding="utf-8")
    ustate = root / "usage.jsonl"
    rec = lambda sid: json.dumps({"ts": "2026-11-04T10:00:00.000Z", "session": sid, "trigger": "bash:cat docs/event-network/offene-punkte.md",
                                  "topics": [{"file": "index-x.md"}], "files": [], "shared": []})
    ustate.write_text("\n".join([rec("u1"), rec("u2"), rec("u3"),
                                  json.dumps({"ts": "2026-10-01T00:00:00.000Z", "session": "u1", "trigger": "bash:x",
                                              "topics": [{"file": "index-x.md"}], "files": [], "record_only": True})]) + "\n",
                      encoding="utf-8")
    u = mu.usage_count(ustate, tdir, mem, since="2026-11-01")
    if u["shown"] == 3 and u["used"] == 2 and u["per_target"][0]["used"] == 2:
        ok("6 --usage: read after the showing (index or linked file) counts, read before or the trigger does not, record-only/old skipped")
    else:
        bad(f"6 usage: {u}")
    # 5
    rc = mu.main(["--dir", (root / "nope").as_posix()])
    if rc == 2:
        ok("5 missing transcript dir -> exit 2")
    else:
        bad(f"5 rc {rc}")

print("memory-usage-test: all green" if fail == 0 else "memory-usage-test: FAILURES")
sys.exit(fail)
