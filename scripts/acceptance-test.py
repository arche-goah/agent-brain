#!/usr/bin/env python3
"""Fixture for scripts/acceptance.py: no acceptance, a thin field, a result changed afterwards (even with the
acceptance touched) and an acceptance copied next to another result must fail; a full acceptance must pass; `open`
must refuse without acceptance (exit 1, nothing opened)."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = str(Path(__file__).resolve().parent / "acceptance.py")


def run(*a):
    return subprocess.run([sys.executable, SCRIPT, *a], capture_output=True, text=True).returncode


d = tempfile.mkdtemp()
img = str(Path(d) / "render.png")
Path(img).write_bytes(b"png")
assert run("check", img) == 1, "no acceptance must fail"
assert run("open", img) == 1, "open without acceptance must refuse"
assert run("write", img, "--inventory", "x", "--facts", "f" * 30, "--fresh-eyes", "e" * 30) == 1, "thin field must fail"
assert run("write", img, "--inventory", "i" * 30, "--facts", "f" * 30, "--fresh-eyes", "e" * 30) == 0, "full must pass"
assert run("check", img) == 0
other = str(Path(d) / "other.png")
Path(other).write_bytes(b"another image")
Path(other + ".acceptance.json").write_bytes(Path(img + ".acceptance.json").read_bytes())
assert run("check", other) == 1, "an acceptance copied next to another result must fail"
Path(img).write_bytes(b"png2")
os.utime(img + ".acceptance.json")
assert run("check", img) == 1, "changed after acceptance must fail, even with the acceptance touched"
assert run("selftest") == 0
print("acceptance-test ok")
