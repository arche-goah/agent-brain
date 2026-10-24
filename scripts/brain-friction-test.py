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

print("brain-friction: blind-to-indirection")

STOP_CHECKS = {"checks": [{"label": "C", "marker": "CLASS-GATE",
                           "cmd": "core/helpers/class-gate.cjs", "mode": "block"}]}
BLIND = ("import json\n# reads settings.json hooks and matches class-gate.cjs by name\n"
         "s = json.load(open('.claude/settings.json'))\n"
         "wired = 'class-gate.cjs' in json.dumps(s.get('hooks', {}))\n")
AWARE = BLIND + "cfg = open('.claude/rules/stop-checks.json').read()\n"
# names the helper only in comments (line and block) — the shape mechanism-guard.cjs had
COMMENT_ONLY = ("const fs = require('fs');\n"
                "const s = JSON.parse(fs.readFileSync('.claude/settings.json')); // hooks\n"
                "// quote shapes are the ones class-gate.cjs accepts\n"
                "/* class-gate.cjs is not read here */\n")


def build_dispatcher_brain(root, scripts):
    (root / ".claude" / "rules").mkdir(parents=True)
    (root / ".claude" / "rules" / "stop-checks.json").write_text(
        json.dumps(STOP_CHECKS), encoding="utf-8")
    (root / "scripts").mkdir()
    for name, body in scripts.items():
        (root / "scripts" / name).write_text(body, encoding="utf-8")


# 5. a checker that reads settings.json and ignores stop-checks.json is blind (negative control)
with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    build_dispatcher_brain(root, {"blind-check.py": BLIND})
    out = scan(root)
    ok("a checker blind to the dispatcher is reported",
       "blind-to-indirection" in out and "blind-check.py" in out,
       "the class this check exists for went silent")

# 6. the same checker that also reads stop-checks.json knows the indirection
with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    build_dispatcher_brain(root, {"aware-check.py": AWARE})
    out = scan(root)
    ok("a checker that reads stop-checks.json stays silent",
       "aware-check.py" not in out,
       "a file that already knows the config was reported blind")

# 7. a helper named only in comments is no match (the false hit of 2026-10-19)
with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    build_dispatcher_brain(root, {"comment-only.cjs": COMMENT_ONLY})
    out = scan(root)
    ok("a helper named only in a comment is not a match",
       "comment-only.cjs" not in out,
       "a comment mention was reported as a blind check")

print("brain-friction: write-only recorders and frequency design")

REC_CHECKS = {"checks": [
    {"label": "R", "marker": "R-GATE", "cmd": "core/helpers/r-gate.cjs", "mode": "record"},
    {"label": "P", "marker": "P-GATE", "cmd": "core/helpers/p-gate.cjs", "mode": "record"},
    {"label": "F", "marker": "F-GATE", "cmd": "core/helpers/f-gate.cjs", "mode": "block"},
]}


def build_recorder_brain(root, files):
    (root / ".claude" / "rules").mkdir(parents=True)
    (root / ".claude" / "rules" / "stop-checks.json").write_text(
        json.dumps(REC_CHECKS), encoding="utf-8")
    for rel, body in files.items():
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_text(body, encoding="utf-8")


GATES = {"core/helpers/r-gate.cjs": "// writes nothing itself\n",
         "core/helpers/p-gate.cjs": "fs.appendFileSync(path.join(d, 'p-own.jsonl'), row)\n",
         "core/helpers/f-gate.cjs": " * Frequency design: once per turn\n"}

# 8. a log named only by a fixture and a changelog is not read (the recall/absence shape)
with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    build_recorder_brain(root, {**GATES,
                                "scripts/test-r-gate.sh": "cat .claude-state/r-gate.jsonl\n",
                                "CHANGELOG.md": "r-gate.jsonl and p-own.jsonl\n"})
    out = scan(root)
    ok("a log mentioned only by a fixture or changelog is write-only",
       "R records" in out and "p-own.jsonl" in out,
       f"output was: {out.strip()[:300]}")

# 9. recorder-report started by a real script reads the dispatcher logs; a skill reads the own log
with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    build_recorder_brain(root, {**GATES,
                                "core/scripts/recorder-report.py": "# reader\n",
                                "core/scripts/brain-scan-prep.py": "run('recorder-report.py')\n",
                                "core/skills/close/SKILL.md": "read .claude-state/p-own.jsonl\n"})
    out = scan(root)
    ok("a run reader and a skill reading the own log silence write-only",
       "write-only (" not in out, f"output was: {out.strip()[:300]}")

# 10. recorder-report present but started by nothing counts as no reader
with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    build_recorder_brain(root, {**GATES, "core/scripts/recorder-report.py": "# reader\n"})
    out = scan(root)
    ok("a reader nobody starts is no reader",
       "R records" in out, f"output was: {out.strip()[:300]}")

# 11. a declared frequency design is no missing cooldown; an undeclared one still is
with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    build_recorder_brain(root, GATES)
    out = scan(root)
    ok("a gate with 'Frequency design:' is not reported without cooldown",
       "f-gate.cjs" not in out, f"output was: {out.strip()[:300]}")
with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    build_recorder_brain(root, {**GATES, "core/helpers/f-gate.cjs": "// blocks always\n"})
    out = scan(root)
    ok("a gate with neither cooldown nor frequency design is still reported",
       "no-cooldown" in out and "f-gate.cjs" in out, f"output was: {out.strip()[:300]}")

if fails:
    print(f"brain-friction-test: {len(fails)} FAILURE(S)")
    sys.exit(1)
print("brain-friction-test: all 12 fixtures passed")
