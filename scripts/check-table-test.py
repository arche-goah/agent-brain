#!/usr/bin/env python3
"""Fixture for check-table.py: positive and negative cases, markdown and JSONL input. Exit 0 = all pass."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

TOOL = str(Path(__file__).with_name("check-table.py"))
HEAD = "| check | device | os | software | commit | date | result | note |\n|---|---|---|---|---|---|---|---|\n"


def doc(rows: list[str], owner: str = "Looks good to me.", req: str = "macOS, Windows") -> str:
    return ("required_os: %s\n\n## Checks\n\n| id | Check |\n|---|---|\n| c1 | first |\n| c2 | second |\n\n"
            "## Results\n\n%s%s\n\n## The owner's word\n\n%s\n" % (req, HEAD, "\n".join(rows), owner))


def row(check, device, os_, date, result):
    return "| %s | %s | %s | 1.0 | abc | %s | %s | |" % (check, device, os_, date, result)


def run(text: str) -> tuple[int, str]:
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "t.md"
        p.write_text(text, encoding="utf-8")
        r = subprocess.run([sys.executable, TOOL, "verdict", str(p)], capture_output=True, text=True, encoding="utf-8")
        return r.returncode, r.stdout


ALL = [row(c, d, o, "2026-10-11", "pass") for c in ("c1", "c2") for d, o in (("mac1", "macOS"), ("win1", "Windows"))]
fails = []


def case(name, got, want, out="", contains=None):
    ok = got == want and (contains is None or contains in out)
    print("%s  %s" % ("ok  " if ok else "FAIL", name))
    if not ok:
        fails.append(name)
        print(out)


rc, out = run(doc(ALL))
case("all pass on both systems, owner recorded = ready", rc, 0, out)

rc, out = run(doc(ALL[:3]))
case("one check lacks Windows = not ready, names the system", rc, 1, out, "no pass yet on: Windows")

rc, out = run(doc(ALL, owner="_not yet recorded_"))
case("owner's word missing = not ready", rc, 1, out, "owner's word is not recorded")

OWNER_TBL = "Intro.\n\n| Question | Suite owner |\n|---|---|\n| Does X belong? | %s |\n| Anything to change? | fine |"
rc, out = run(doc(ALL, owner=OWNER_TBL % "open"))
case("owner section with an `open` row = not ready, names the question", rc, 1, out, "open question: Does X belong?")

rc, out = run(doc(ALL, owner=OWNER_TBL % ""))
case("owner section with an empty answer = not ready", rc, 1, out, "open question")

rc, out = run(doc(ALL, owner=OWNER_TBL % "yes, as written"))
case("owner section with every row answered = ready", rc, 0, out)

rc, out = run(doc(ALL + [row("c1", "win1", "Windows", "2026-10-12", "fail — crashes")]))
case("later fail on the same device reopens the check", rc, 1, out, "RED")

rc, out = run(doc([row("c1", "win1", "Windows", "2026-10-10", "fail — crashes"),
                   row("c1", "win1", "Windows", "2026-10-12", "pass")] + ALL[1:]
                  + [row("c1", "mac1", "macOS", "2026-10-11", "pass")]))
case("fail then later pass on the same device is resolved", rc, 0, out)

rc, out = run(doc(ALL + [row("c1", "win2", "Windows", "2026-10-12", "fail — other box")]))
case("a fail on a second device of the same OS stays open", rc, 1, out, "win2")

rc, out = run(doc([ALL[0]] + ALL[2:] + [row("c1", "x", "Windows", "2026-10-11", "n/a")]))
case("n/a without a reason does not count", rc, 1, out, "LACKS")

rc, out = run(doc([r for r in ALL if "win1" not in r or "c2" in r] + [row("c1", "x", "Windows", "2026-10-11", "n/a — no such feature")]))
case("n/a with a reason satisfies the OS", rc, 0, out)

rc, out = run(doc(ALL + [row("c1", "lin1", "Linux", "2026-10-11", "fail — odd")], req="macOS, Windows"))
case("an OS that is not required still keeps a fail open", rc, 1, out, "RED")

rc, out = run(doc([r.replace("macOS", "macos") for r in ALL]))
case("OS compare is case-insensitive", rc, 0, out)

rc, out = run(doc(ALL).replace("required_os: macOS, Windows\n", ""))
case("no required_os line = unreadable, never ready", rc, 2, out)

rc, out = run(doc(ALL).replace("## Results", "## Something else"))
case("no Results table = unreadable", rc, 2, out)

rc, out = run(doc(ALL + [HEAD.splitlines()[0]]))
case("a repeated header row is not read as data", rc, 0, out)

rc, out = run(doc(ALL + ["| c1 | w | Windows | someday | pass | |"]))
case("a row without a date is skipped with a note, not counted", rc, 0, out, "skipped")

# JSONL path + render round trip
with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    (d / "c.json").write_text(json.dumps({"required_os": ["macOS", "Windows"],
                                          "checks": [{"id": "c1", "check": "first"}, {"id": "c2", "check": "second"}]}), encoding="utf-8")
    keys = ("check", "device", "os", "software", "commit", "date", "result", "note")
    recs = [dict(zip(keys, [c, dv, o, "1.0", "abc", "2026-10-11", "pass", "a|b"])) for c in ("c1", "c2")
            for dv, o in (("mac1", "macOS"), ("win1", "Windows"))]
    (d / "r.jsonl").write_text("\n".join(json.dumps(r) for r in recs) + "\n", encoding="utf-8")
    (d / "o.txt").write_text("Fine.", encoding="utf-8")
    r = subprocess.run([sys.executable, TOOL, "verdict", "--results", str(d / "r.jsonl"), "--checks", str(d / "c.json"),
                        "--owner-file", str(d / "o.txt")], capture_output=True, text=True, encoding="utf-8")
    case("jsonl input, ready", r.returncode, 0, r.stdout)
    r = subprocess.run([sys.executable, TOOL, "render", "--results", str(d / "r.jsonl"), "--checks", str(d / "c.json"),
                        "--owner-file", str(d / "o.txt")], capture_output=True, text=True, encoding="utf-8")
    (d / "t.md").write_text(r.stdout, encoding="utf-8")
    r2 = subprocess.run([sys.executable, TOOL, "verdict", str(d / "t.md")], capture_output=True, text=True, encoding="utf-8")
    case("rendered markdown reads back as ready (pipe in a note survives)", r2.returncode, 0, r2.stdout)
    r3 = subprocess.run([sys.executable, TOOL, "verdict", "--results", str(d / "missing.jsonl"), "--checks", str(d / "c.json")],
                        capture_output=True, text=True, encoding="utf-8")
    case("missing results file = unreadable", r3.returncode, 2, r3.stdout)

print("\ncheck-table-test: %s" % ("FAILED: " + ", ".join(fails) if fails else "all passed"))
sys.exit(1 if fails else 0)
