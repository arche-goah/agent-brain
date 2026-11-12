#!/usr/bin/env python3
"""Fixture for the ledger-field grammar: the `_cases` of ledger-fields.json read the same in Python
(scripts/ledger_fields.py) and JavaScript (helpers/ledger-fields.cjs), and each reader that moved onto it still
finds a mid-line id. Exit 1 on a failed case."""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import ledger_fields  # noqa: E402

fails = 0


def check(label, cond):
    global fails
    print(("  OK   " if cond else "  FAIL ") + label)
    fails += 0 if cond else 1


spec = json.load(open(os.path.join(ROOT, "ledger-fields.json"), encoding="utf-8"))
cases = spec["_cases"]
js = subprocess.run(
    ["node", "-e", "const {firstValue}=require(process.argv[1]);const c=JSON.parse(process.argv[2]);"
     "process.stdout.write(JSON.stringify(c.map((x)=>firstValue(x.text,'id'))))",
     os.path.join(ROOT, "helpers", "ledger-fields.cjs"), json.dumps(cases)],
    capture_output=True, text=True, encoding="utf-8")
got_js = json.loads(js.stdout or "[]")
for i, c in enumerate(cases):
    py = ledger_fields.first_value(c["text"], "id")
    check(f"python {c['text']!r} -> {c['id']!r}", py == c["id"])
    check(f"javascript reads it the same ({got_js[i] if i < len(got_js) else 'missing'!r})", i < len(got_js) and got_js[i] == c["id"])

check("several values in order", ledger_fields.field_values("  id: a\n- x | id: b | class: todo", "id") == ["a", "b"])
print("ledger-fields-test: " + ("all checks passed" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
