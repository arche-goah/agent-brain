#!/usr/bin/env python3
"""Fixture for helpers/plan-label-gate.cjs: a read plan with uncertainty labels is named, both directions."""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
GATE = HERE.parent / "helpers" / "plan-label-gate.cjs"
fails = 0
total = 0


def check(name, ok):
    global fails, total
    total += 1
    print(("  OK   " if ok else "  FAIL ") + name)
    fails += 0 if ok else 1


def run(root, file, tool="Read"):
    env = dict(os.environ, CLAUDE_PROJECT_DIR=str(root))
    inp = {"hook_event_name": "PostToolUse", "tool_name": tool, "tool_input": {"file_path": str(file)}}
    r = subprocess.run(["node", str(GATE)], input=json.dumps(inp), capture_output=True, text=True, encoding="utf-8", env=env)
    return r.returncode, r.stdout.strip()


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    (root / ".claude" / "rules").mkdir(parents=True)
    docs = root / "docs"
    docs.mkdir()

    order = docs / "order-list.md"
    order.write_text("| part | link |\n| clip 10x | search hit, page not read |\n| tape | https://shop.example/p/tape-1 |\n"
                     "| cable | part number open |\n", encoding="utf-8")
    rc, out = run(root, order)
    check("a plan with labels is named (the incident shape)", rc == 0 and "carries 2 line(s)" in out)
    check("the named lines carry their line numbers", "L2:" in out and "L4:" in out and "L3:" not in out)

    clean = docs / "order-list-clean.md"
    clean.write_text("| part | link |\n| tape | https://shop.example/p/tape-1 |\n", encoding="utf-8")
    rc, out = run(root, clean)
    check("a plan without labels stays silent (control)", rc == 0 and out == "")

    notes = docs / "meeting-notes.md"
    notes.write_text("search hit, page not read\n", encoding="utf-8")
    rc, out = run(root, notes)
    check("a file that is no plan stays silent (control)", out == "")

    rc, out = run(root, order, tool="Edit")
    check("another tool than Read stays silent (control)", out == "")

    de = docs / "achats" / "besoin.md"
    de.parent.mkdir()
    de.write_text("| pièce | lien |\n| pince | résultat de recherche · page non lue |\n", encoding="utf-8")
    rc, out = run(root, de)
    check("an instance path without instance data stays silent (control)", out == "")
    (root / ".claude" / "rules" / "plan-labels.json").write_text(
        json.dumps({"plan_paths": ["/achats/"], "labels": ["résultat de recherche", "non lue"]}), encoding="utf-8")
    rc, out = run(root, de)
    check("instance data adds a plan path and labels in its own language (non-ASCII read as UTF-8)", "carries 1 line(s)" in out)

    (root / ".claude" / "rules" / "plan-labels.json").write_text(json.dumps({"enabled": False}), encoding="utf-8")
    rc, out = run(root, order)
    check("enabled false turns it off", out == "")

    rc, out = run(root, docs / "missing-plan.md")
    check("a missing file fails open", rc == 0 and out == "")

print(f"\n{total - fails}/{total} passed")
sys.exit(1 if fails else 0)
