#!/usr/bin/env python3
"""covers: lesson-carriers
Both directions on a synthetic protocol: an entry with a `Carrier:` line is carried, one with a
second key word from instance data too, one with "Carrier: prose, because …" is carried (a
decision, not a gap), an entry
without the line is loose and named with date and title, --since drops older entries, a heading
without a date is no entry, an unreadable protocol is said and exits 0, instance data renames
the key. Negative control: with the carrier keys emptied every entry turns loose.
Run: scripts/lesson-carriers-test.py    Exit 0 = all green.
"""
from __future__ import annotations
import importlib.util
import io
import contextlib
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("lc", ROOT / "scripts" / "lesson-carriers.py")
lc = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lc)
fails = 0


def check(cond, name):
    global fails
    print(f"  {'ok  ' if cond else 'FAIL'}  {name}")
    fails += 0 if cond else 1


def run(repo: Path, *args):
    out = io.StringIO()
    sys.argv = ["lesson-carriers.py", "--repo", str(repo), *args]
    with contextlib.redirect_stdout(out):
        rc = lc.main()
    return rc, out.getvalue()


PROTO = """# Feedback protocol

## Event rules (chronological)

## 2026-10-01 — First lesson with a check
Occasion: something.
Carrier: core/scripts/foo.py (check 3).

## 2026-10-02 — Second lesson, second key word from instance data
Bearer: helpers/bar-gate.cjs

## 2026-10-03 — Third lesson, prose on purpose
Rule: only so.
Carrier: prose, because it is a matter of the operator's taste.

## 2026-10-04 — Fourth lesson without a carrier
Rule: anything.
Reach: this brain only.

## 2026-10-05 — Fifth lesson, bold key
**Carrier:** memory `x` + gate.
"""

with tempfile.TemporaryDirectory() as d:
    repo = Path(d)
    (repo / "docs" / "maintenance").mkdir(parents=True)
    (repo / "docs" / "maintenance" / "feedback-protocol.md").write_text(PROTO, encoding="utf-8")
    rules = repo / ".claude" / "rules"
    rules.mkdir(parents=True)
    (rules / "lesson-carriers.json").write_text(json.dumps({"carrier_keys": ["Carrier", "Bearer"]}), encoding="utf-8")

    rc, out = run(repo)
    check(rc == 0, "exit 0 (a report)")
    check("summary: entries=5 carried=4 loose=1" in out, f"four carried, one loose: {out.strip().splitlines()[-1]}")
    check("lesson without carrier: 2026-10-04 — Fourth lesson without a carrier" in out, "the loose entry is named with date and title")
    check("2026-10-02" not in out, "a second key word from instance data counts")
    check("2026-10-03" not in out, "'prose, because' counts as a carrier (a decision, not a gap)")
    check("2026-10-05" not in out, "a bold **Carrier:** line counts")

    rc, out = run(repo, "--since", "2026-10-05")
    check("entries=1 carried=1 loose=0" in out, "--since drops older entries")

    rc, out = run(repo, "--json")
    data = json.loads(out)
    check(data["loose"] == [{"date": "2026-10-04", "title": "Fourth lesson without a carrier"}], "--json lists the loose entry")
    check(data["entries"] == 5, "the dateless section heading is not an entry")

    # defaults only (no instance data): the second key word is unknown -> that entry turns loose
    (rules / "lesson-carriers.json").unlink()
    rc, out = run(repo)
    check("entries=5 carried=3 loose=2" in out, "without instance data only the built-in key word counts")

    # negative control: instance data with another key word only -> every entry is loose
    (rules / "lesson-carriers.json").write_text(json.dumps({"carrier_keys": ["Mechanism"]}), encoding="utf-8")
    rc, out = run(repo)
    check("entries=5 carried=0 loose=5" in out, "negative control: with another key word every entry is loose")
    (rules / "lesson-carriers.json").unlink()

    # unreadable protocol: said, exit 0
    rc, out = run(repo, "--protocol", str(repo / "nope.md"))
    check(rc == 0 and "NOT checked" in out, "an unreadable protocol is said, never read as clean")

    # second source: feedback memories name their carrier in metadata.carrier
    check("lesson-carriers memory:" not in out, "no memory folder -> no memory line (the temp repo has none)")
    mem = repo / "mem"
    mem.mkdir()
    (repo / "helpers").mkdir()
    (repo / "helpers" / "bar-gate.cjs").write_text("// refuses X before Y\n", encoding="utf-8")

    def memory(name, mtype, carrier=None, modified="2026-10-20"):
        extra = f"\n  carrier: {carrier}" if carrier is not None else ""
        (mem / name).write_text(f"---\nname: {name[:-3]}\ndescription: d\nmetadata:\n  type: {mtype}{extra}\n"
                                f"  modified: {modified}T10:00:00Z\n---\n\nbody\n", encoding="utf-8")

    memory("fb-carried.md", "feedback", "helpers/bar-gate.cjs :: refuses X before Y")
    memory("fb-prose.md", "feedback", "prose, because it is the operator's taste")
    memory("fb-none.md", "feedback")
    memory("fb-file-gone.md", "feedback", "helpers/gone.cjs :: refuses X")
    memory("fb-phrase-gone.md", "feedback", "helpers/bar-gate.cjs :: allows everything")
    memory("fb-free-text.md", "feedback", "the gate")
    memory("fb-old.md", "feedback", modified="2026-09-01")
    memory("project-fact.md", "project")
    (mem / "MEMORY.md").write_text("- [x](fb-none.md)\n", encoding="utf-8")
    (mem / "index-feedback.md").write_text("---\nname: index-feedback\nmetadata:\n  type: feedback\n---\n", encoding="utf-8")

    rc, out = run(repo, "--memory", str(mem))
    check(rc == 0 and "lesson-carriers memory: memories=7 carried=2 loose=5" in out,
          f"seven feedback memories, two carried (file+phrase, prose): {out.strip().splitlines()[-1]}")
    check("memory without carrier: fb-none.md - no metadata.carrier" in out, "a missing field is named")
    check("fb-file-gone.md - carrier file helpers/gone.cjs missing" in out, "a missing carrier file is named")
    check("fb-phrase-gone.md - phrase not in helpers/bar-gate.cjs" in out, "a phrase the file does not hold is named")
    check("fb-free-text.md - carrier 'the gate' is not" in out, "free text without '::' is named")
    check("fb-carried.md" not in out and "fb-prose.md" not in out, "carried memories stay silent")
    check("project-fact.md" not in out and "index-feedback.md" not in out and "MEMORY.md" not in out,
          "other types, the index and topic indexes are not checked")
    check("lesson-carriers summary: entries=5" in out, "the protocol line is unchanged by the memory source")

    rc, out = run(repo, "--memory", str(mem), "--since", "2026-10-15")
    check("lesson-carriers memory: memories=6" in out, "--since drops a memory modified before it (fb-old)")

    rc, out = run(repo, "--memory", str(mem), "--json")
    data = json.loads(out)
    check(data["memory"]["memories"] == 7 and len(data["memory"]["loose"]) == 5, "--json carries the memory block")

    # negative control: instance data names another type -> nothing is checked, the line says 0
    (rules / "lesson-carriers.json").write_text(json.dumps({"memory_types": ["user"]}), encoding="utf-8")
    rc, out = run(repo, "--memory", str(mem))
    check("lesson-carriers memory: memories=0 carried=0 loose=0" in out, "negative control: memory_types decides what is checked")
    (rules / "lesson-carriers.json").unlink()

print("lesson-carriers-test: " + ("all checks passed" if fails == 0 else f"{fails} check(s) FAILED"))
sys.exit(1 if fails else 0)
