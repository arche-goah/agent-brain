#!/usr/bin/env python3
"""Fixture for english-only.py: an untracked text file is NAMED as not checked, never failed.

Both directions: without untracked files the output is the plain clean line (no note);
with an untracked .py the note names it and the exit stays 0; an untracked file whose
suffix the ratchet never reads stays unnamed. The script runs from a copy inside a
throwaway git repo, because it judges the repo it sits in.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.stdout.reconfigure(encoding="utf-8", newline="\n")   # the smoke greps these lines
fails = 0


def check(name, cond, detail=""):
    global fails
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  -- {detail}"))
    if not cond:
        fails += 1


def run(repo, *args):
    # The script prints an em dash; on Windows a redirected stdout uses the ANSI codepage
    # unless pinned (docs/os-traps.md OS-9), so the child is pinned to UTF-8 here.
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    env.pop("ENGLISH_ONLY_BASE", None)   # the host's CI setting must not reach the fixture
    p = subprocess.run([sys.executable, str(repo / "scripts" / "english-only.py"), *args],
                       capture_output=True, text=True, encoding="utf-8", errors="replace", env=env)
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

    # Line ratchet (2026-10-25): a legacy file may not GAIN German. Measured on a suite PR that
    # added a German line to a baseline file and stayed green under the file-level rule.
    legacy = repo / "docs" / "legacy.md"
    legacy.parent.mkdir(parents=True, exist_ok=True)
    legacy.write_text("# Legacy\n\nDas ist fuer uns noch nicht uebersetzt.\n", encoding="utf-8")
    (repo / "scripts" / "english-legacy.txt").write_text("docs/legacy.md\n", encoding="utf-8")
    git(repo, "add", "-A")
    git(repo, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "base")
    rc, out = run(repo, "--base", "HEAD")
    check("line ratchet: an unchanged legacy file is clean against its base", rc == 0, out)
    legacy.write_text(legacy.read_text(encoding="utf-8") + "Eine neue Zeile ueber das Geraet.\n", encoding="utf-8")
    git(repo, "add", "-A")
    rc, out = run(repo, "--base", "HEAD")
    check("line ratchet: a new German line in a legacy file fails against the base",
          rc == 1 and "NEW GERMAN LINES: docs/legacy.md (+1" in out, out)
    rc, out = run(repo)
    check("control: without a base the file-level rule alone holds (legacy file passes)", rc == 0, out)
    legacy.write_text("# Legacy\n\nAn English line first.\nDas ist fuer uns noch nicht uebersetzt.\n", encoding="utf-8")
    git(repo, "add", "-A")
    rc, out = run(repo, "--base", "HEAD")
    check("control: an English line added and a German line moved is not new German", rc == 0, out)
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("english-only: all checks passed" if not fails else f"english-only: {fails} check(s) FAILED")
sys.exit(1 if fails else 0)
