#!/usr/bin/env python3
"""The settings template's main-push ask rules, against the commands they must and must not catch.

WHY (measured 2026-10-30 on the macOS instance): the old rules `git push * main*` asked on any later text
starting with "main" (a branch `maintenance-fix`, a comment), and missed `git push origin feat/x:main` (a push
of another branch onto main: no space before "main"). The new rules ask on `main` as a word or `:main`.
`*` is matched as "any characters", the way the permission globs read it.

    python3 scripts/template-push-ask-test.py   (exit 0 = all pass)
"""
import fnmatch
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ask = json.loads((ROOT / "templates" / "settings.json").read_text(encoding="utf-8"))["permissions"]["ask"]
pats = [m.group(1) for r in ask if (m := re.fullmatch(r"Bash\((.*)\)", r)) and "push" in r and "main" in r]

CASES = [
    ("git -C /r push origin main", True),
    ("git -C /r push origin main # note", True),
    ("git -C /r push origin HEAD:main", True),
    ("git push origin feat/x:main", True),
    ("git -C /r push origin maintenance-fix", False),
    ("git -C /r push -u origin fix/main-loop", False),
    ("git -C /r push https://github.com/o/r.git fix/x:fix/x", False),
]
fail = 0
for cmd, want in CASES:
    got = any(fnmatch.fnmatchcase(cmd, p) for p in pats)
    print(("  ok  " if got == want else "  FAIL") + f" {'asks' if want else 'free'}: {cmd}")
    fail |= got != want
ps = [r for r in ask if r.startswith("PowerShell(") and "push" in r and "main" in r]
if sorted(r[len("PowerShell("):] for r in ps) != sorted(r[len("Bash("):] for r in ask if r.startswith("Bash(") and "push" in r and "main" in r):
    print("  FAIL PowerShell twins differ from the Bash rules")
    fail = 1
else:
    print("  ok   every Bash rule has its PowerShell twin")
print("template-push-ask: " + ("FAILED" if fail else "all pass"))
sys.exit(fail)
