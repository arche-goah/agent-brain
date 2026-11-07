#!/usr/bin/env python3
"""covers: claim-lint

Fixtures for claim-lint.py, both directions.

  1. no block anywhere -> exit 0, "nothing to check"
  2. a clean block (English methods) and an `unsupported` block without evidence -> exit 0
  3. each of the three rules fires on its own block, the form checks (missing field, unknown value)
  4. instance data: aliases in another language map to the methods; without them the same word is
     unknown (the language comes from the data, not the code); a none word empties independence
  5. the declared schema is named, skipped as a source, and a declared path into nothing is a finding
  6. a placeholder block (`id: <...>`) is a template, never checked

Usage: python3 scripts/claim-lint-test.py   (exit 0 = all fixtures pass)
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass

LINT = Path(__file__).resolve().parent / "claim-lint.py"
fails = []


def ok(n, cond, detail=""):
    print(f"  {'ok  ' if cond else 'FAIL'}  {n}{'' if cond else ': ' + detail}")
    if not cond:
        fails.append(n)


def run(root, *args):
    p = subprocess.run([sys.executable, str(LINT), "--root", str(root), *args],
                       capture_output=True, text=True, encoding="utf-8")
    return p.returncode, p.stdout + p.stderr


def block(cid, assessment="accepted", risk="low", method="measured", retrieved="2026-01-02 10:00",
          reviewed="2026-01-02 11:00", independence="", evidence=1):
    ev = "".join(f"  - source: probe {i}\n    method: {method}\n    retrieved_at: {retrieved}\n"
                 f"    value: 4 ms\n" for i in range(evidence))
    return (f"```claim\nid: {cid}\nstatement: the path carries 4 ms\nassessment: {assessment}\n"
            f"risk: {risk}\n" + (f"evidence:\n{ev}" if evidence else "") +
            f"reviewed_at: {reviewed}\n" + (f"independence: {independence}\n" if independence else "") + "```\n")


def brain(td, docs, cfg=None):
    root = Path(td)
    (root / "docs").mkdir(parents=True, exist_ok=True)
    (root / "docs" / "runlog.md").write_text("# runlog\n\n" + docs, encoding="utf-8")
    if cfg is not None:
        (root / ".claude" / "rules").mkdir(parents=True, exist_ok=True)
        (root / ".claude" / "rules" / "claim-schema.json").write_text(json.dumps(cfg), encoding="utf-8")
    return root


print("claim-lint")
with tempfile.TemporaryDirectory() as td:
    rc, out = run(brain(td, "no blocks here\n"))
    ok("no block: exit 0, nothing to check", rc == 0 and "no claim block found" in out, out)

with tempfile.TemporaryDirectory() as td:
    docs = block("clean") + "\n```claim\nid: unknown-cause\nstatement: cause unknown\nassessment: unsupported\n" \
        "risk: medium\nreviewed_at: 2026-01-02 11:00\n```\n"
    rc, out = run(brain(td, docs))
    ok("a clean block and an unsupported block without evidence pass", rc == 0 and "2 claim block(s), 0 finding(s)" in out, out)

with tempfile.TemporaryDirectory() as td:
    docs = (block("r1", method="assumed") + block("r2", retrieved="2026-01-03 09:00")
            + block("r3", risk="high") + block("r3-ok", risk="high", evidence=2, independence="two clocks")
            + "```claim\nid: form\nassessment: sure\nrisk: low\nreviewed_at: 2026-01-02\n```\n")
    rc, out = run(brain(td, docs))
    ok("RULE 1: assumed evidence under accepted", "[r1]: RULE 1" in out, out)
    ok("RULE 2: retrieved after reviewed", "[r2]: RULE 2" in out, out)
    ok("RULE 3: high risk accepted with one piece of evidence", "[r3]: RULE 3" in out, out)
    ok("RULE 3 negative control: two pieces + independence pass", "[r3-ok]" not in out, out)
    ok("form: missing fields and an unknown assessment", "[form]: required field missing: statement, evidence" in out
       and "assessment 'sure' unknown" in out, out)
    ok("findings exit 1 and print !! lines", rc == 1 and out.count("!! ") == 5, out)

with tempfile.TemporaryDirectory() as td:
    docs = block("de", method="medido") + block("de-hedge", method="supuesto") \
        + block("none", risk="high", evidence=2, independence="ninguna")
    root = brain(td, docs)
    rc, out = run(root)
    ok("without aliases a word of another language is an unknown method", "method 'medido' unknown" in out, out)
    ok("without none_words 'ninguna' counts as filled independence", "[none]" not in out, out)
    (root / ".claude" / "rules").mkdir(parents=True)
    (root / ".claude" / "rules" / "claim-schema.json").write_text(json.dumps({
        "method_aliases": {"medido": "measured", "supuesto": "assumed"}, "none_words": ["ninguna"]}), encoding="utf-8")
    rc, out = run(root)
    ok("aliases map the brain's words to the methods", "'medido' unknown" not in out and "[de]" not in out, out)
    ok("an aliased hedge word still trips RULE 1", "[de-hedge]: RULE 1" in out, out)
    ok("a none word empties independence (RULE 3)", "[none]: RULE 3" in out, out)

with tempfile.TemporaryDirectory() as td:
    root = brain(td, block("clean"), {"schema": "docs/schema.md"})
    (root / "docs" / "schema.md").write_text("# schema\n\n" + block("in-the-schema", method="assumed"), encoding="utf-8")
    rc, out = run(root)
    ok("the declared schema is named and skipped as a source", rc == 0 and "form: docs/schema.md" in out
       and "1 claim block(s)" in out, out)
    (root / ".claude" / "rules" / "claim-schema.json").write_text(json.dumps({"schema": "docs/gone.md"}), encoding="utf-8")
    rc, out = run(root)
    ok("a declared schema path into nothing is a finding", rc == 1 and "'docs/gone.md' does not exist" in out, out)

with tempfile.TemporaryDirectory() as td:
    rc, out = run(brain(td, "```claim\nid: <short unique id>\nassessment: accepted | provisional\n```\n"))
    ok("a placeholder block is a template, never checked", rc == 0 and "no claim block found" in out, out)

print()
print("claim-lint fixtures: " + ("ALL passed" if not fails else f"{len(fails)} FAILED"))
sys.exit(1 if fails else 0)
