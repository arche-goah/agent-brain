#!/usr/bin/env python3
"""Fixtures for backprop-report.py — both directions.

  1. A new dated rule line with a marked term lists the OTHER place that names the term.
  2. The new line itself is never listed as its own hit.
  3. An undated added line is no rule: nothing reported (control).
  4. A dated line without a marked term says so instead of searching silently.
  5. Nothing changed: the "no new dated rule line" message.
  6. A rule file not yet tracked counts as all-new.

Usage: python3 scripts/backprop-report-test.py   (exit 0 = all fixtures pass)
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import git_sandbox  # noqa: E402,F401 - the host git config never reaches a fixture repo

SCRIPT = HERE / "backprop-report.py"
fails = []


def ok(n, cond, detail=""):
    print(f"  {'ok  ' if cond else 'FAIL'}  {n}{'' if cond else ': ' + detail}")
    if not cond:
        fails.append(n)


def git(root, *a):
    subprocess.run(["git", "-C", str(root), *a], check=True, capture_output=True)


def write(p, text):
    p.parent.mkdir(parents=True, exist_ok=True)
    with open(p, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def run(root, *extra):
    r = subprocess.run([sys.executable, str(SCRIPT), "--root", str(root), *extra],
                       capture_output=True, text=True, encoding="utf-8")
    return r.returncode, r.stdout


with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    git(root, "init", "-q")
    write(root / "rules" / "feedback.md", "# Feedback\n\n- old rule\n")
    write(root / "rules" / "other.md", "The `merge-gate` blocks every merge.\nUnrelated line.\n")
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "base")
    args = ["--search", "rules", "rules/feedback.md"]

    rc, out = run(root, *args)
    ok("5 nothing changed says so", rc == 0 and "no new dated rule line" in out, out)

    write(root / "rules" / "feedback.md",
          "# Feedback\n\n- old rule\n- 2026-10-21: the `merge-gate` now allows squash.\n"
          "- an undated note about `merge-gate`\n- 2026-10-21: plain words only\n")
    rc, out = run(root, *args)
    ok("1 the other place that names the term is listed", "rules/other.md:1" in out, out)
    ok("2 the new line is not its own hit", "rules/feedback.md:4" not in out, out)
    ok("3 the undated line is no rule", out.count("NEW ") == 2, out)
    ok("4 a dated line without a marked term says so", "no marked term" in out, out)
    ok("   exit 0 always", rc == 0, str(rc))

    write(root / "rules" / "fresh.md", "- 2026-10-21: **Unrelated line** is now a rule.\n")
    rc, out = run(root, "--search", "rules", "rules/fresh.md")
    ok("6 an untracked rule file counts as all-new", "NEW rules/fresh.md" in out and "rules/other.md:2" in out, out)

    # 7. a bold phrase written nowhere else word for word: its long words are searched and the line
    #    says so (macOS counter-check on #71) — a bare "no other place" read as "nothing to supersede"
    write(root / "rules" / "neighbour.md", "The waiting list lives in open-items data.\n")
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "more")
    with open(root / "rules" / "feedback.md", "a", encoding="utf-8", newline="\n") as fh:
        fh.write("- 2026-10-22: **Every waiting entry names its date** now.\n")
    rc, out = run(root, *args)
    ok("7 a phrase without a twin falls back to its words", "not written elsewhere as a phrase" in out
       and "'waiting': rules/neighbour.md:1" in out, out)

print()
if fails:
    print(f"backprop-report: {len(fails)} fixture(s) FAILED")
    sys.exit(1)
print("backprop-report: all fixtures pass")
