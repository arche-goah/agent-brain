#!/usr/bin/env python3
"""Fixture tests for scripts/brain-scan-prep.py — every rule has a case that MUST fire and a
neighbour that must stay silent (a check tested only against its trigger is a check that
might fire on everything).

Covered: the return channel (vanished / still-open / done / dropped / decided, legacy report
without index, today's own report not counted), the third-recurrence decision, the four
deep-check triggers with their thresholds (5 vs 4 new rules, memory index near the limit,
rebuild-ahead, a finding back a third time), "not available" reported once on an old core,
and the mapping of machine-check output into findings.
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

PREP = str(Path(__file__).resolve().parent / "brain-scan-prep.py")
fails = 0


def check(cond, name):
    global fails
    print(("  OK   " if cond else "  FAIL ") + name)
    if not cond:
        fails += 1


def write(p, text):
    p = Path(p)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")


def report(repo, date, keys):
    """keys: [(key, exit)] -> a report with a finding index."""
    lines = [f"# Brain-Scan Report — {date}", "", "## Finding index", ""]
    lines += [f"- key: {k} | severity: P2 | exit: {e} | title: finding {k}" for k, e in keys]
    write(Path(repo) / f"docs/research/brain-scan/scan-{date}.md", "\n".join(lines) + "\n")


def orders(repo, body):
    write(Path(repo) / "docs/maintenance/brain-scan-auftraege.md",
          "# Orders\n\n## Open (ordered)\n\n## Proposed (derived)\n\n" + body + "\n## Done\n\n")


def run(repo, *extra, core=None, mem=None):
    out = Path(repo) / "_out"
    args = [sys.executable, PREP, "--repo", str(repo), "--out", str(out), "--today", "2026-10-09",
            "--memory-dir", str(mem or Path(repo) / "_mem")]
    if core:
        args += ["--core", str(core)]
    p = subprocess.run(args + list(extra), capture_output=True, text=True, encoding="utf-8")
    last = p.stdout.strip().splitlines()[-1] if p.stdout.strip() else "{}"
    summ = json.loads(last).get("brain_scan_prep", {})
    rc = json.loads((out / "return-channel.json").read_text(encoding="utf-8"))
    mach = json.loads((out / "scan-machine.json").read_text(encoding="utf-8"))
    head = (out / "report-machine.md").read_text(encoding="utf-8")
    return p.returncode, summ, rc, mach, head


def state(rc, key):
    return {r["key"]: r["state"] for r in rc["earlier"]}.get(key)


def deep(summ, check_name):
    return [l for l in summ.get("deep_check", []) if l.startswith(f"deep check suggested: {check_name} — ")]


with tempfile.TemporaryDirectory() as d:
    # ── return channel ──────────────────────────────────────────────────────
    r = Path(d) / "rc"
    report(r, "2026-10-01", [("gone", "ai-does-it"), ("tracked", "ai-does-it"), ("fixed", "ai-does-it"),
                             ("dropme", "drop"), ("settled", "operator-decision"), ("already", "done-already")])
    report(r, "2026-10-09", [("gone", "ai-does-it")])  # today's own report: never "previous"
    orders(r, "- [ ] **tracked**\n  id: tracked\n\n- [x] **fixed**\n  id: fixed\n\n"
              "- [ ] **settled**\n  id: settled\n  decided 2026-10-05: accepted as is\n")
    code, summ, rc, mach, head = run(r, "--skip-machine")
    check(code == 0, "exit 0")
    check(rc["previous_report"].endswith("scan-2026-10-01.md"), "today's own report is not the previous one")
    check(state(rc, "gone") == "vanished", "a finding in the report and nowhere else is VANISHED")
    check(state(rc, "tracked") == "still-open", "a finding with an open order entry is still-open, not vanished")
    check(state(rc, "fixed") == "done", "a checked order entry is done")
    check(state(rc, "already") == "done", "exit done-already is done")
    check(state(rc, "dropme") == "dropped", "exit drop is dropped")
    check(state(rc, "settled") == "decided", "a decided marker on the entry is decided")
    check(summ.get("states", {}).get("vanished") == 1, "summary counts the vanished one")
    check("vanished: `gone`" in head, "report head lists the vanished finding")

    # instance marker data (other languages): a German drop marker
    write(r / ".claude/rules/brain-scan-prep.json", json.dumps({"dropped": [r"\bgestrichen\b"]}))
    orders(r, "- [ ] **tracked**\n  id: tracked\n  gestrichen 2026-10-06\n")
    _, _, rc, _, _ = run(r, "--skip-machine")
    check(state(rc, "tracked") == "dropped", "an instance marker (data, not code) marks dropped")

    # legacy report without index
    lg = Path(d) / "legacy"
    write(lg / "docs/research/brain-scan/scan-2026-10-01.md", "# old\n\n1. **[P1] something**\n")
    _, summ, rc, _, head = run(lg, "--skip-machine")
    check(rc["previous_has_index"] is False and rc["earlier"] == [], "a legacy report without index yields no rows")
    check("has no finding index" in head, "legacy report says once that tracing starts now")

    # ── third recurrence -> decision ────────────────────────────────────────
    t = Path(d) / "third"
    report(t, "2026-09-24", [("again", "ai-does-it")])
    report(t, "2026-10-01", [("again", "ai-does-it"), ("once", "ai-does-it")])
    orders(t, "- [ ] **again**\n  id: again\n\n- [ ] **once**\n  id: once\n")
    _, summ, rc, _, _ = run(t, "--skip-machine")
    check("again" in summ.get("decision_due", []), "seen in two earlier reports, unfixed: decision-due (this run = third time)")
    check("once" not in summ.get("decision_due", []), "seen once: not decision-due")
    check(not deep(summ, "coherence-scan"), "two appearances do not yet suggest a deep check")
    report(t, "2026-10-05", [("again", "ai-does-it")])
    _, summ, _, _, _ = run(t, "--skip-machine")
    check(any("came back a third time" in l for l in deep(summ, "coherence-scan")),
          "three appearances without a fix suggest a coherence-scan")
    orders(t, "- [x] **again**\n  id: again\n")
    _, summ, _, _, _ = run(t, "--skip-machine")
    check("again" not in summ.get("decision_due", []), "a fixed recurrer is no decision")

    # ── deep check: new dated rules, 5 fires, 4 stays silent ────────────────
    for n, expect in ((5, True), (4, False)):
        c = Path(d) / f"rules{n}"
        write(c / "docs/research/coherence-scan/register-2026-09-18.md", "# register\n")
        write(c / "CLAUDE.md", "- old rule (2026-09-01)\n")
        write(c / ".claude/rules/feedback.md",
              "".join(f"- rule {i} (operator 2026-10-0{i + 1})\n" for i in range(n)) + "- older (2026-09-10)\n")
        _, summ, _, _, head = run(c, "--skip-machine")
        got = deep(summ, "coherence-scan")
        check(bool(got) == expect, f"{n} new dated rules: deep-check line {'present' if expect else 'absent'}")
        if expect:
            check("~2.6M tokens per run" in got[0] and "(2026-09-18)" in got[0], "the line names why and the measured price")
            check(got[0] in head, "the line reaches the report head verbatim")

    # memory index near the limit
    m = Path(d) / "mem"
    write(m / "_mem/MEMORY.md", "- x\n" * 185)
    _, summ, _, _, _ = run(m, "--skip-machine")
    check(bool(deep(summ, "memory-dream")), "memory index at 185/200 lines suggests memory-dream")
    write(m / "_mem/MEMORY.md", "- x\n" * 100)
    _, summ, _, _, _ = run(m, "--skip-machine")
    check(not deep(summ, "memory-dream"), "memory index at 100/200 lines stays silent")

    # rebuild ahead
    b = Path(d) / "rebuild"
    orders(b, "- [ ] **split the core** rebuild-ahead\n  id: split\n")
    _, summ, _, _, _ = run(b, "--skip-machine")
    check(bool(deep(summ, "full-audit")), "an open rebuild-ahead entry suggests full-audit")
    orders(b, "- [x] **split the core** rebuild-ahead\n  id: split\n")
    _, summ, _, _, _ = run(b, "--skip-machine")
    check(not deep(summ, "full-audit"), "a finished rebuild stays silent")

    # ── machine checks ──────────────────────────────────────────────────────
    old = Path(d) / "oldcore"
    (old / "scripts").mkdir(parents=True)
    _, summ, _, mach, _ = run(b, core=old)
    na = [f for f in mach["findings"] if f["title"].startswith("not available in this core checkout")]
    check(len(na) == 1 and all(n in na[0]["title"] for n in ("local-machinery.py", "commitments.py", "brain-selftest.sh")),
          "an old core: ONE 'not available' line naming the missing scripts")

    stub = Path(d) / "stubcore"
    write(stub / "scripts/local-machinery.py",
          "print('!! shadow: scripts/x.py has the name of a core script')\nprint('local machinery summary: shadow=1')\n")
    write(stub / "scripts/commitments.py",
          "print('loose commitment: from now on I do X')\nprint('commitments summary: found=1 carried=0 loose=1')\n")
    write(stub / "scripts/brain-selftest.sh", "echo '  !!  fixture x failed'\necho 'SELF-TEST: FAILURE'\nexit 1\n")
    write(stub / "scripts/effect-check.sh", "echo 'ROT  E3  Hook Targets — 1 missing'\necho 'OK   E1  Style — ok'\n"
                                            "echo 'WARN E6  Loose Commitments — 1'\nexit 1\n")
    write(stub / "scripts/invariant-check.py", "import sys\nprint('  !!  C-1\\n      NEW site: a.sh (2 hits)')\n"
                                               "print('      -> MECHANISM due (>=3 sites or repeat after a fix)')\nsys.exit(1)\n")
    write(b / "docs/maintenance/invariants.md", "root: .\n")
    _, summ, _, mach, _ = run(b, core=stub)
    T = {f["title"]: f["severity"] for f in mach["findings"]}
    has = lambda sev, part: any(s == sev and part in t for t, s in T.items())
    check(has("P1", "local-machinery: !! shadow"), "a loud local-machinery line is a P1 finding")
    check(has("P2", "commitments: loose commitment"), "a loose commitment is a P2 finding")
    check(has("P1", "brain-selftest failed: !!  fixture x failed"), "a failing self-test is P1 with its line")
    check(has("P1", "effect-check E3") and has("OK", "effect-check E1"), "effect-check ROT -> P1, OK lines summarised")
    check(not any("E6" in t for t in T), "effect-check E6 is not doubled when commitments ran directly")
    check(has("P1", "invariant register drift") and has("P2", "MECHANISM due"), "register drift P1, mechanism due P2")
    check(not any(t.startswith("not available") for t in T), "a complete core reports nothing as unavailable")
    check(summ.get("machine_p1") == sum(1 for s in T.values() if s == "P1"), "summary P1 count = file P1 count")

    crashcore = Path(d) / "crashcore"
    write(crashcore / "scripts/brain-selftest.sh", "echo 'bash: line 3: unbound variable'\nexit 2\n")
    _, _, _, mach, _ = run(b, core=crashcore)
    check(any("brain-selftest.sh did not complete (rc=2)" in f["title"] for f in mach["findings"]),
          "a crashed check reads as a crash, not as a finding about the brain")

print(f"brain-scan-prep-test: {'all checks passed' if not fails else f'{fails} FAILED'}")
sys.exit(1 if fails else 0)
