#!/usr/bin/env python3
"""Every Path.read_text / Path.write_text in the core's Python names its encoding.

Without `encoding=`, Python uses the platform's locale codec: UTF-8 on macOS and Linux,
cp1252 on Windows. A fixture that writes `·` or an em dash then hands the reader a byte it
cannot decode, and a correct reader fails only on Windows (2026-11-06: release-scope-test.py,
23/27 on Windows, 27/27 everywhere else; docs/os-traps.md OS-23). The scan reads the AST, so a
call split over several lines counts like a one-line call.
"""
import ast
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def unencoded(src, name):
    """(line, method) of each read_text/write_text call without an encoding."""
    hits = []
    for n in ast.walk(ast.parse(src, name)):
        if (isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
                and n.func.attr in ("read_text", "write_text")
                and not any(k.arg == "encoding" for k in n.keywords)
                # positional encoding: read_text(encoding), write_text(data, encoding)
                and len(n.args) < (1 if n.func.attr == "read_text" else 2)):
            hits.append((n.lineno, n.func.attr))
    return hits


fails = 0


def check(name, ok):
    global fails
    print(("  OK   " if ok else "  FAIL ") + name)
    fails += 0 if ok else 1


# Negative control: the scanner must see the defect, one-line and split over lines.
bad = 'from pathlib import Path\nPath("a").write_text("x ·")\nPath("b").write_text(\n    "y"\n)\nPath("c").read_text()\n'
good = 'from pathlib import Path\nPath("a").write_text("x", encoding="utf-8")\nPath("c").read_text("utf-8")\n'
check("a write_text without encoding is found (one line and split)", sorted(h[0] for h in unencoded(bad, "bad")) == [2, 3, 6])
check("a call with encoding (keyword or positional) passes", unencoded(good, "good") == [])
with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp) / "planted.py"
    p.write_text(bad, encoding="utf-8")
    check("a planted file is read from disk like a repo file", len(unencoded(p.read_text(encoding="utf-8"), str(p))) == 3)

files = subprocess.run(["git", "-C", str(ROOT), "ls-files", "*.py"], capture_output=True, text=True, check=True).stdout.split()
found = []
for f in files:
    path = ROOT / f
    if not path.is_file():
        continue
    try:
        src = path.read_text(encoding="utf-8")
        hits = unencoded(src, f)
    except (SyntaxError, UnicodeDecodeError):
        continue
    found += [f"{f}:{line} {meth}" for line, meth in hits]
check(f"every read_text/write_text in the core names its encoding ({len(files)} files)", not found)
for h in found:
    print("       " + h + ' - add encoding="utf-8"')

total = 4
print(f"\n{total - fails}/{total} passed")
sys.exit(1 if fails else 0)
