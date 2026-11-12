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
        # The builtin open() in text mode has the same platform default (2026-11-11: check-catalog-test.py,
        # 9/18 on Windows at the 2.1.5 train head; the scan saw only read_text/write_text, so the lint passed).
        # Binary mode carries no encoding; encoding= or the 4th positional (file, mode, buffering, encoding) passes.
        elif (isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id == "open"
                and not any(k.arg == "encoding" for k in n.keywords) and len(n.args) < 4):
            mode = n.args[1] if len(n.args) > 1 else next((k.value for k in n.keywords if k.arg == "mode"), None)
            if isinstance(mode, ast.Constant) and isinstance(mode.value, str) and "b" in mode.value:
                continue
            if mode is not None and not isinstance(mode, ast.Constant):
                continue  # a computed mode cannot be judged here
            hits.append((n.lineno, "open"))
    return hits


def stream_pins(src, name):
    """Names of the std streams a script pins with `sys.<stream>.reconfigure(...)`."""
    pins = set()
    for n in ast.walk(ast.parse(src, name)):
        if (isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr == "reconfigure"
                and isinstance(n.func.value, ast.Attribute) and isinstance(n.func.value.value, ast.Name)
                and n.func.value.value.id == "sys"):
            pins.add(n.func.value.attr)
    return pins


# OS-9, stderr half (2026-11-12): a script that pins stdout but not stderr still writes its error
# lines in the platform codec. The CI fixture loop runs Python under PYTHONIOENCODING=cp1252;
# start-findings.py pinned stdout only, an error line with an em dash left as 0x97, and the test
# that decodes UTF-8 crashed (agent-brain #522, ubuntu). 66 scripts had the same shape.
def stderr_unpinned(src, name):
    pins = stream_pins(src, name)
    return "stdout" in pins and "stderr" not in pins


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
bad_open = 'open("a", "w")\nopen("b")\nopen(\n    "c", mode="r"\n)\n'
good_open = 'open("a", "w", encoding="utf-8")\nopen("b", "rb")\nopen("c", mode="wb")\nopen("d", "r", -1, "utf-8")\n'
check("an open() in text mode without encoding is found (one line and split)", sorted(h[0] for h in unencoded(bad_open, "bad_open")) == [1, 2, 3])
check("an open() with encoding, or in binary mode, passes", unencoded(good_open, "good_open") == [])
pin_out = 'import sys\nsys.stdout.reconfigure(encoding="utf-8")\n'
pin_both = pin_out + 'try:\n    sys.stderr.reconfigure(encoding="utf-8")\nexcept ValueError:\n    pass\n'
check("a script pinning stdout but not stderr is reported", stderr_unpinned(pin_out, "pin_out"))
check("a script pinning both streams, or neither, passes",
      not stderr_unpinned(pin_both, "pin_both") and not stderr_unpinned("import sys\n", "none"))
with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp) / "planted.py"
    p.write_text(bad, encoding="utf-8")
    check("a planted file is read from disk like a repo file", len(unencoded(p.read_text(encoding="utf-8"), str(p))) == 3)

files = subprocess.run(["git", "-C", str(ROOT), "ls-files", "*.py"], capture_output=True, text=True, check=True).stdout.split()
found = []
unpinned = []
for f in files:
    path = ROOT / f
    if not path.is_file():
        continue
    try:
        src = path.read_text(encoding="utf-8")
        hits = unencoded(src, f)
        if stderr_unpinned(src, f):
            unpinned.append(f)
    except (SyntaxError, UnicodeDecodeError):
        continue
    found += [f"{f}:{line} {meth}" for line, meth in hits]
check(f"every read_text/write_text/text-mode open() in the core names its encoding ({len(files)} files)", not found)
for h in found:
    print("       " + h + ' - add encoding="utf-8"')

check(f"every script that pins stdout also pins stderr ({len(files)} files)", not unpinned)
for f in unpinned:
    print("       " + f + ' - add sys.stderr.reconfigure(encoding="utf-8") next to the stdout pin')

total = 9
print(f"\n{total - fails}/{total} passed")
sys.exit(1 if fails else 0)
