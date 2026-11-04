#!/usr/bin/env python3
"""Fixture for shared-memory-archive.py — both directions, sandbox only.
covers: scripts/shared-memory-archive.py

Proves: a dry run moves nothing and names the candidates; --write moves the settled old message
with git mv and leaves the open one, the young one and the durable one; a rerun moves nothing; the
moved reply still settles its request (OPEN.md, index line); the index lists the month's archived
messages as one line, not one per entry; a `related` that names the moved file still resolves.
Exit 0 = all pass.
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
from importlib import import_module
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import git_sandbox  # noqa: E402,F401 - the host git config never reaches a fixture repo

smi = import_module("shared-memory-index")
sml = import_module("shared-memory-lint")
SCRIPT = HERE / "shared-memory-archive.py"
fails = 0


def ok(name: str, cond: bool, detail: str = "") -> None:
    global fails
    print(f"  {'ok  ' if cond else 'FAIL'}  {name}" + ("" if cond else f": {detail[:300]}"))
    fails += 0 if cond else 1


def git(repo: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=True).stdout


def entry(repo: Path, area: str, name: str, date: str, extra: str = "") -> None:
    (repo / area).mkdir(parents=True, exist_ok=True)
    text = (f"---\nname: {name}\ndescription: \"{name} text\"\nmetadata:\n  type: project\n  von: kim-pc\n"
            f"  audience: sam-laptop\n  topic: {area}\n  date: {date}\n{extra}---\n\nbody\n")
    with open(repo / area / f"{name}.md", "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def run(repo: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(SCRIPT), "--repo", str(repo), "--today", "2026-11-04", *args],
                          capture_output=True, text=True)


with tempfile.TemporaryDirectory() as td:
    repo = Path(td) / "shared"
    repo.mkdir()
    git(repo, "init", "-q")
    entry(repo, "ops", "request-old", "2026-10-01", "  status: open\n  next: sam-laptop\n")
    entry(repo, "ops", "reply-old", "2026-10-02", "  answers: ops/request-old\n")
    entry(repo, "ops", "request-still-open", "2026-10-01", "  status: open\n  next: sam-laptop\n")
    entry(repo, "ops", "note-young", "2026-11-01")
    entry(repo, "ops", "decision-durable", "2026-09-01", "  status: decided\n")
    entry(repo, "ops", "reply-later", "2026-11-02", "  related: [ops/reply-old.md]\n")
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "seed")

    r = run(repo)
    ok("1 dry run names the settled old messages and moves nothing",
       r.returncode == 0 and "ops/request-old.md" in r.stdout and "ops/reply-old.md" in r.stdout
       and "dry run" in r.stdout and (repo / "ops" / "request-old.md").is_file(), r.stdout + r.stderr)
    ok("2 dry run leaves the open, the young and the durable out",
       "request-still-open" not in r.stdout and "note-young" not in r.stdout and "decision-durable" not in r.stdout,
       r.stdout)

    r = run(repo, "--write")
    moved_req = repo / "ops" / "archive" / "2026-10" / "request-old.md"
    moved_rep = repo / "ops" / "archive" / "2026-10" / "reply-old.md"
    ok("3 --write moves the two settled old messages into <area>/archive/<yyyy-mm>/ by git mv",
       r.returncode == 0 and moved_req.is_file() and moved_rep.is_file()
       and not (repo / "ops" / "request-old.md").exists()
       and "R" in git(repo, "status", "--porcelain").split("ops/request-old.md")[0][-3:], r.stdout + r.stderr
       + git(repo, "status", "--porcelain"))
    ok("4 the open, the young and the durable entry stay in place",
       (repo / "ops" / "request-still-open.md").is_file() and (repo / "ops" / "note-young.md").is_file()
       and (repo / "ops" / "decision-durable.md").is_file())
    r2 = run(repo, "--write")
    ok("5 a rerun moves nothing", r2.returncode == 0 and "nothing to move" in r2.stdout, r2.stdout + r2.stderr)

    root, topics, entries, opens = smi.build(repo, today="2026-11-04")
    ix = topics["ops"]
    ok("6 the moved reply still settles its request: not in OPEN.md, and the open list holds only the live one",
       "(../ops/request-still-open.md)" in opens["ops"] and "request-old" not in opens["ops"], opens["ops"])
    ok("7 the index lists the archived month as one line, not one line per moved entry",
       "### 2026-10 (2)" in ix and "2 archived in [archive/2026-10/](archive/2026-10/)" in ix
       and "(../ops/archive/2026-10/request-old.md)" not in ix, ix)
    line = next(ln for ln in ix.splitlines() if "(../ops/reply-later.md)" in ln)
    ok("8 a `related` naming the moved file still resolves, to its new path",
       "related: [reply old](../ops/archive/2026-10/reply-old.md)" in line, line)
    ok("9 the lint's resolve_target finds a moved stem without a stems map",
       sml.resolve_target("ops/reply-old.md", repo) == "ops/archive/2026-10/reply-old.md",
       str(sml.resolve_target("ops/reply-old.md", repo)))
    ok("10 the index pages were regenerated by the move (OPEN.md on disk names the live request only)",
       (repo / "ops" / "OPEN.md").is_file() and "request-old" not in (repo / "ops" / "OPEN.md").read_text(encoding="utf-8")
       and "request-still-open" in (repo / "ops" / "OPEN.md").read_text(encoding="utf-8"))

print()
print(f"shared-memory-archive: {'all fixtures pass' if not fails else str(fails) + ' fixture(s) FAILED'}")
sys.exit(1 if fails else 0)
