#!/usr/bin/env python3
"""Fixture for english-only.py: an untracked text file is NAMED as not checked, never failed.

Both directions: without untracked files the output is the plain clean line (no note);
with an untracked .py the note names it and the exit stays 0; an untracked file whose
suffix the ratchet never reads stays unnamed. The script runs from a copy inside a
throwaway git repo, because it judges the repo it sits in.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
fails = 0


def check(name, cond, detail=""):
    global fails
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  -- {detail}"))
    if not cond:
        fails += 1


def run(repo):
    p = subprocess.run([sys.executable, str(repo / "scripts" / "english-only.py")],
                       capture_output=True, text=True, encoding="utf-8")
    return p.returncode, p.stdout


def git(repo, *args):
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)


tmp = Path(tempfile.mkdtemp())
try:
    repo = tmp / "repo"
    (repo / "scripts").mkdir(parents=True)
    shutil.copy(HERE / "english-only.py", repo / "scripts" / "english-only.py")
    (repo / "scripts" / "english-legacy.txt").write_text("", encoding="utf-8")
    (repo / "scripts" / "english-legacy-names.txt").write_text("", encoding="utf-8")
    (repo / "README.md").write_text("An English readme.\n", encoding="utf-8")
    git(repo, "init", "-q")
    git(repo, "add", "-A")

    rc, out = run(repo)
    check("clean tree: exit 0", rc == 0, out)
    check("clean tree: no note when nothing is untracked", "NOT checked" not in out, out)

    (repo / "scripts" / "new-tool.py").write_text("print('hello')\n", encoding="utf-8")
    (repo / "image.bin").write_bytes(b"\x00\x01")
    rc, out = run(repo)
    check("untracked .py: exit stays 0 (named, not failed)", rc == 0, out)
    check("untracked .py: the note names it", "scripts/new-tool.py" in out and "NOT checked" in out, out)
    check("untracked .bin: a suffix the ratchet never reads is not named", "image.bin" not in out, out)

    git(repo, "add", "-A")
    rc, out = run(repo)
    check("staged: the note is gone", "NOT checked" not in out, out)
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("english-only: all checks passed" if not fails else f"english-only: {fails} check(s) FAILED")
sys.exit(1 if fails else 0)
