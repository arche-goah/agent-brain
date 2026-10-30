#!/usr/bin/env python3
"""Fixture for instance-templates.py: covered, optional, known gap, new gap, stale gap — positive control included."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "instance-templates.py"


def run(files, decl):
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        for rel, text in files.items():
            p = root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text, encoding="utf-8")
        (root / "templates" / "rules-instance").mkdir(parents=True, exist_ok=True)
        if decl is not None:
            (root / "templates" / "instance-files-optional.json").write_text(json.dumps(decl), encoding="utf-8")
        r = subprocess.run([sys.executable, str(SCRIPT), str(root)], capture_output=True, text=True)
        return r.returncode, r.stdout


READER = {
    "helpers/a.cjs": "path.join(root, '.claude', 'rules', 'alpha.json')\n",
    "scripts/b.py": "p = root / '.claude/rules/beta.json'\n",
    "templates/rules-instance/alpha.json": "{}\n",
}
cases = [
    ("covered by template and optional reason", READER, {"optional": {"beta.json": "built-ins"}}, 0, "2 covered"),
    ("new read without template fails (positive control)", READER, {}, 1, "!! beta.json"),
    ("known gap in unclassified passes", READER, {"unclassified": ["beta.json"]}, 0, "1 known unclassified"),
    ("covered name still listed is stale", READER, {"optional": {"beta.json": "x"}, "unclassified": ["beta.json"]}, 0, "-- beta.json"),
    ("fixture files are not readers", {**READER, "scripts/b.py": "", "scripts/b-test.py": "'.claude/rules/beta.json'"}, {}, 0, "1 read"),
    ("missing declaration file", READER, None, 1, "!! beta.json"),
]
fail = 0
for name, files, decl, want_rc, want_text in cases:
    rc, out = run(files, decl)
    ok = rc == want_rc and want_text in out
    fail += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {name}" + ("" if ok else f" — rc={rc} out={out!r}"))
print(f"instance-templates-test: {len(cases) - fail}/{len(cases)} passed")
sys.exit(1 if fail else 0)
