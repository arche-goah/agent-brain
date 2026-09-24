#!/usr/bin/env python3
"""Fixtures for brain-friction.py, allowlist-contradiction branch.

The check's own wording draws the line: "being USED by another tool is fine; being
scheduled behind the operator's back is not". Until 2026-09-24 the code did not draw
it — ANY caller counted, so a hand tool that has an effect proof reported against its
own fixture. That put two mechanisms of this repo against each other: brain-selftest
demands a fixture for every mechanism, and doing the right thing then produced a
permanent friction candidate on every instance carrying one.

Four fixtures, each a pair of the only two answers that matter:

  1. fixture-only caller      -> SILENT   (the case that was wrong)
  2. real caller              -> REPORTED (the case that must survive)
  3. both callers present     -> REPORTED, and the REAL one is named, not the fixture
  4. allowlisted file missing -> stale-allowlist still fires (sibling branch intact)

Usage: python3 scripts/brain-friction-test.py   (exit 0 = all fixtures pass)
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

# OS-9: a Python script whose stdout another program reads pins it — on Windows a
# redirected stdout otherwise takes the ANSI codepage and CRLF, and the runner that
# collects fixture output would see different bytes per platform. The duty is the
# producer's; a consumer cannot repair bytes that already left wrong.
try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):  # a stream that cannot be reconfigured
    pass

HERE = Path(__file__).resolve().parent
SCANNER = HERE / "brain-friction.py"

fails = []


def ok(n, cond, detail=""):
    print(f"  {'ok  ' if cond else 'FAIL'}  {n}{'' if cond else ': ' + detail}")
    if not cond:
        fails.append(n)


def build_brain(root, callers, handtool="handtool.sh", create_handtool=True):
    """A throwaway brain: one allowlisted hand tool plus the given caller scripts."""
    rules = root / ".claude" / "rules"
    rules.mkdir(parents=True)
    (rules / "manual-tools.json").write_text(
        json.dumps({"manual": [handtool]}), encoding="utf-8")
    scripts = root / "scripts"
    scripts.mkdir()
    if create_handtool:
        (scripts / handtool).write_text("#!/bin/bash\necho hand tool\n", encoding="utf-8")
    for name, body in callers.items():
        (scripts / name).write_text(body, encoding="utf-8")


def scan(root):
    # The scanner chdir()s into its target, so it is run as a subprocess against a
    # throwaway tree rather than imported — importing would move THIS process.
    res = subprocess.run([sys.executable, str(SCANNER), str(root)],
                         capture_output=True, text=True, encoding="utf-8",
                         errors="replace")
    return res.stdout + res.stderr


CALL = "#!/bin/bash\nbash scripts/handtool.sh\n"

print("brain-friction: allowlist-contradiction")

# 1. a fixture calling the hand tool is not a scheduler
with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    build_brain(root, {"test-handtool.sh": CALL, "handtool-test.sh": CALL})
    out = scan(root)
    ok("fixture-only caller stays silent",
       "allowlist-contradiction" not in out,
       "a hand tool called only by its own test was reported as a contradiction")

# 2. a real caller is still a finding
with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    build_brain(root, {"nightly.sh": CALL})
    out = scan(root)
    ok("real caller is reported",
       "allowlist-contradiction" in out and "nightly.sh" in out,
       "a non-fixture caller must stay a candidate — this is the case the check is for")

# 3. with both present the REAL caller is the one named. The names are chosen so the
#    fixture sorts FIRST: the scanner reports callers[0], so with the obvious names
#    ("nightly.sh" before "test-...") this case passes even unpatched and proves
#    nothing. Measured 2026-09-24 — the first draft of this fixture was green against
#    the broken scanner for exactly that reason.
with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    build_brain(root, {"test-aaa-handtool.sh": CALL, "zzz-nightly.sh": CALL})
    out = scan(root)
    line = next((l for l in out.splitlines() if "invoked by" in l), "")
    ok("the named caller is the real one, not the fixture",
       "allowlist-contradiction" in out and "zzz-nightly.sh" in line
       and "test-aaa-handtool.sh" not in line,
       f"reported line was: {line.strip() or '(none)'}")

# 4. the sibling branch of the same block still works
with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    build_brain(root, {}, create_handtool=False)
    out = scan(root)
    ok("missing allowlisted file still reports stale-allowlist",
       "stale-allowlist" in out,
       "the other half of the allowlist block was broken by the filter")

if fails:
    print(f"brain-friction-test: {len(fails)} FAILURE(S)")
    sys.exit(1)
print("brain-friction-test: all 4 fixtures passed")
