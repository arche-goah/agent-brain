#!/usr/bin/env python3
"""Fixture for scripts/acceptance.py: no acceptance, a thin field and a result changed afterwards must fail; a full,
fresh acceptance must pass; `open` must refuse without acceptance (exit 1, nothing opened)."""
import os
import subprocess
import sys
import tempfile
import time
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
time.sleep(1.1)
Path(img).write_bytes(b"png2")
assert run("check", img) == 1, "changed after acceptance must fail"
assert run("selftest") == 0
print("acceptance-test ok")
