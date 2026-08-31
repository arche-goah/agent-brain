#!/usr/bin/env python3
"""Fixtures for os-traps-export.py.

The exporter writes into a repo a second instance reads, so the same three properties
that bit the other generator apply: LF endings, a frontmatter `name` that matches the
filename it is written to (the shared-memory linter checks exactly that), and no silent
success on input it did not understand.

The fourth case is the one specific to this tool: an entry without a `shape` must be
VISIBLE, not quietly filed under a shrug — an unclassified trap is the finding, since the
whole point of the shapes is that a new platform is searched in a known order.

Usage: python3 scripts/os-traps-export-test.py   (exit 0 = all fixtures pass)
"""
import importlib.util
import io
import contextlib
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("ote", HERE / "os-traps-export.py")
ote = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ote)

fails = []


def ok(n, cond, detail=""):
    print(f"  {'ok  ' if cond else 'FAIL'}  {n}{'' if cond else ': ' + detail}")
    if not cond:
        fails.append(n)


REGISTER = """root: ..

## OS-1 — first trap

invariant: something
shape: A
pattern:   x
paths:     .
known:
instances: 4
repeat:    yes
status:    closed

## OS-9 — unclassified trap

invariant: something else
pattern:   y
paths:     .
known:
instances: 1
repeat:    no
status:    open
"""


def run(args):
    old = sys.argv
    sys.argv = ["os-traps-export.py"] + args
    out, err = io.StringIO(), io.StringIO()
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = ote.main()
    finally:
        sys.argv = old
    return rc, out.getvalue(), err.getvalue()


print("os-traps-export:")

with tempfile.TemporaryDirectory() as td:
    reg = Path(td) / "os-traps.md"
    reg.write_text(REGISTER, encoding="utf-8", newline="\n")
    dest = Path(td) / "shared" / "core" / "os-trap-register.md"

    rc, out, err = run(["--register", str(reg), "--out", str(dest), "--write"])
    ok("1 exits 0 on a valid register", rc == 0, f"rc={rc} {err[:120]}")
    ok("2 both entries parsed", "OS-1" in dest.read_text(encoding="utf-8")
       and "OS-9" in dest.read_text(encoding="utf-8"), "an entry is missing")

    raw = dest.read_bytes()
    ok("3 written with LF", b"\r" not in raw,
       f"{raw.count(bytes([13]))} CR byte(s)")

    text = dest.read_text(encoding="utf-8")
    ok("4 frontmatter name matches the filename it writes",
       f"name: {dest.stem}" in text, text.split(chr(10))[1] if text else "")

    ok("5 the classified entry is grouped under its shape",
       "**A · " in text and "OS-1" in text.split("**A · ")[1].split(chr(10))[0],
       "OS-1 not listed under A")

    ok("6 an entry without a shape is visible, not silently grouped",
       "OS-9" in err or "?" in text,
       "no warning and no '?' — an unclassified trap vanished")

    # Negative control: a register the parser does not understand must not produce a
    # confident-looking file. Silence plus exit 0 is the failure mode that matters.
    empty = Path(td) / "empty.md"
    empty.write_text("root: ..\n\nnothing here\n", encoding="utf-8", newline="\n")
    rc2, _, err2 = run(["--register", str(empty), "--out", str(dest), "--write"])
    ok("7 a register with no entries fails loudly", rc2 != 0 and "no entries" in err2,
       f"rc={rc2} err={err2[:80]}")

print()
if fails:
    print(f"os-traps-export: {len(fails)} fixture(s) FAILED")
    sys.exit(1)
print("os-traps-export: all fixtures pass")
