#!/usr/bin/env python3
"""Fixture tests for scripts/state-prose-lint.py — both directions.

Must report: an expired dated state, a state whose date disagrees with local-machinery.json, the
instance's own words through data. Must stay quiet: a consistent dated state, a date without a state
word, the instance's words without the data file (control).
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

LINT = Path(__file__).resolve().parent / "state-prose-lint.py"
TODAY = "2026-10-26"


def run(rules, alphas=None, words=None):
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / ".claude/rules").mkdir(parents=True)
        (root / ".claude/rules/rules.md").write_text(rules, encoding="utf-8")
        (root / "CLAUDE.md").write_text("# brain\n", encoding="utf-8")
        if alphas is not None:
            (root / ".claude/rules/local-machinery.json").write_text(json.dumps({"alpha": alphas}), encoding="utf-8")
        if words is not None:
            (root / ".claude/rules/state-prose.json").write_text(json.dumps(words), encoding="utf-8")
        p = subprocess.run([sys.executable, str(LINT), "--repo", d, "--today", TODAY],
                           capture_output=True, text=True)
        return p.returncode, p.stdout


def case(title, ok, out):
    print(("ok  " if ok else "FAIL") + "  " + title + ("" if ok else "\n" + out))
    return ok


GATE = {"scripts/hooks/own-gate.cjs": {"until": "2026-11-08"}}
results = []
rc, out = run("- a gate, alpha until 2026-10-20: own-gate.cjs\n")
results.append(case("expired dated state reported", rc == 0 and "has passed" in out, out))
rc, out = run("- a gate, alpha until 2026-11-01: `scripts/hooks/own-gate.cjs`\n", GATE)
results.append(case("date disagreeing with local-machinery.json reported", "local-machinery.json says 2026-11-08" in out, out))
rc, out = run("- a gate, alpha until 2026-11-08: `scripts/hooks/own-gate.cjs`\n", GATE)
results.append(case("consistent dated state stays quiet", "state in prose:" not in out and "lines=1" in out, out))
rc, out = run("- released until 2026-10-01, nothing about state\n")
results.append(case("a date without a state word is not a state", "lines=0" in out, out))
de = "- Traeger geparkt bis 2026-10-01\n"
rc, out = run(de, words={"state_words": ["geparkt"], "until_words": ["bis"]})
results.append(case("instance words through data: German expired state reported", "has passed" in out, out))
rc, out = run(de)
results.append(case("control: the same German line without the data file stays quiet", "lines=0" in out, out))
sys.exit(0 if all(results) else 1)
