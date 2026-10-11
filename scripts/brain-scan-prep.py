#!/usr/bin/env python3
"""brain-scan-prep.py — the deterministic half of the brain-scan: return channel, machine
checks and deep-check recommendation, before any judging agent spends a token.

WHY (audit of the audit process, measured 2026-10-09 on the proving brain):
  * The scan was a one-way funnel. Three producers appended proposals to the order list,
    nobody read their outcome: 68 proposals lay 3-5 weeks, 13 of them already done without
    anyone noticing, about a quarter of report-only measures vanished silently, and the
    same finding was reported up to ten times (CLAUDE.md size, hard-coded paths 9 -> 111
    lines) without ever becoming a decision. So every run now STARTS with what became of
    the last run's findings, and a finding seen a third time is a decision, not a line.
  * Two checklist sections (invariant register, self-check) had no executor at all, and
    the "MECHANISM due" lines of the register reached nobody. They are scripts — they run
    here, with the boundary detectors (local machinery, loose commitments) next to them.
  * The context-gathering agent cost ~121k tokens per run for reading three files.
  * The deep-check triggers (coherence-scan after many new rules, ...) were prose; the
    coherence trigger had been torn for weeks and no report said so.

What it does (read-only on the brain; writes only into --out):
  1. RETURN CHANNEL — reads the newest earlier report's finding index and the order list,
     and states per earlier finding: done / decided / dropped / still-open / vanished
     (vanished = it stood in the report and nowhere else). Counts in how many earlier
     reports each key appeared; seen twice and not settled = decision-due (if the scan
     finds it again, that is the third time).
  2. MACHINE CHECKS — effect-check, invariant-check (instance register), brain-selftest,
     local-machinery, commitments; each turned into findings of the scan's finding shape.
     A script absent from this core checkout is reported ONCE as "not available".
  3. DEEP CHECK — one deterministic line per triggered deep check, with why and the price
     measured on the proving brain. It never starts anything.

Finding index (written by the report stage, read here on the next run) — one line each,
under a heading `## Finding index`:
    - key: <slug> | severity: <P0|P1|P2|INFO> | exit: <exit> | title: <title>
Exits (skill backlog-catch-up): done-already, ai-does-it, other-side, parked,
later-at-system, drop, operator-decision.
Order-list entries reference a finding by `id: <key>`. Markers for decided/dropped are
English built in; other languages are instance data in `.claude/rules/brain-scan-prep.json`
{"decided": [regex...], "dropped": [regex...]}.
An unchecked order-list entry containing the token `rebuild-ahead` announces a structural
rebuild (deep-check trigger for full-audit).

Usage: brain-scan-prep.py --out DIR [--repo DIR] [--today YYYY-MM-DD] [--core DIR]
                          [--memory-dir DIR] [--skip-machine]
Writes: <out>/return-channel.json, <out>/scan-machine.json, <out>/report-machine.md
Prints: human lines, then ONE last line: {"brain_scan_prep": {...}} (small summary).
Exit 0 always — a scan must still run when a check cannot.
"""
import argparse
import concurrent.futures
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")  # OS-9: cp1252 + CRLF on Windows
except (AttributeError, ValueError):
    pass

EXITS = ("done-already", "ai-does-it", "other-side", "parked", "later-at-system", "drop",
         "operator-decision")
INDEX_LINE = re.compile(r"^- key: ([a-z0-9][a-z0-9-]*) \| severity: (P0|P1|P2|INFO) \| "
                        r"exit: ([a-z-]+) \| title: (.*)$")
DATE = re.compile(r"\b(20\d\d-\d\d-\d\d)\b")
DECIDED = [r"\bdecided\b", r"\bdecision taken\b"]
DROPPED = [r"\bdropped\b", r"\bsuperseded\b", r"\bwithdrawn\b"]
# Measured on the proving brain, 2026-08 .. 2026-10, fresh tokens per completed run
# (audit-audit 2026-10-09, efficiency part). The price differs per subscription; the
# operator weighs it against their plan.
PRICE = {"brain-scan": 1.5, "memory-dream": 0.6, "coherence-scan": 2.6, "full-audit": 6.0}
NEW_RULES_MIN = 5
MEM_LINES, MEM_BYTES, MEM_NEAR = 200, 25600, 0.9


def read(p):
    try:
        return Path(p).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def report_date(p):
    m = DATE.search(Path(p).name)
    return m.group(1) if m else ""


def parse_index(text):
    """The finding index of one report: {key: {severity, exit, title}}; None = no index."""
    if not re.search(r"^## Finding index\s*$", text, re.M):
        return None
    out = {}
    for line in text.splitlines():
        m = INDEX_LINE.match(line.strip())
        if m:
            out[m.group(1)] = {"severity": m.group(2), "exit": m.group(3), "title": m.group(4).strip()}
    return out


def parse_orders(text):
    """Order-list entries: [{checked, section, text, ids}] — an entry is a `- [ ]`/`- [x]`
    line plus every following line up to the next entry or heading."""
    entries, cur, section = [], None, ""
    for line in text.splitlines():
        if line.startswith("## "):
            section, cur = line[3:].strip(), None
            continue
        m = re.match(r"^- \[([ xX])\]", line)
        if m:
            cur = {"checked": m.group(1) != " ", "section": section, "text": line}
            entries.append(cur)
        elif cur is not None:
            cur["text"] += "\n" + line
    for e in entries:
        e["ids"] = set(re.findall(r"^\s*id:\s*([A-Za-z0-9][A-Za-z0-9_.-]*)", e["text"], re.M))
    return entries


def ordered_open(entries):
    """Unchecked items in the ordered section — German or English template heading."""
    return [e for e in entries if not e["checked"] and re.match(r"(Open|Offen)\b", e["section"])]


def title_of(entry):
    m = re.search(r"\*\*(.+?)\*\*", entry["text"])
    return (m.group(1) if m else entry["text"].splitlines()[0])[:120]


def return_channel(reports, orders, markers):
    """State of every finding of the newest indexed earlier report."""
    indexed = [(p, parse_index(read(p))) for p in reports]
    latest = reports[-1] if reports else None
    latest_index = indexed[-1][1] if indexed else None
    seen = {}
    for _, idx in indexed:
        for k in (idx or {}):
            seen[k] = seen.get(k, 0) + 1
    rows = []
    if latest_index:
        by_id = {}
        for e in orders:
            for i in e["ids"]:
                by_id.setdefault(i, []).append(e)
        for key, f in latest_index.items():
            hits = by_id.get(key, [])
            text = "\n".join(e["text"] for e in hits)
            if f["exit"] == "done-already" or any(e["checked"] or re.match(r"(Done|Erledigt)\b", e["section"]) for e in hits):
                state = "done"
            elif f["exit"] == "drop" or any(re.search(r, text, re.I) for r in markers["dropped"]):
                state = "dropped"
            elif hits and any(re.search(r, text, re.I) for r in markers["decided"]):
                state = "decided"
            elif hits:
                state = "still-open"
            else:
                state = "vanished"
            rows.append({"key": key, "title": f["title"], "severity": f["severity"], "exit": f["exit"],
                         "state": state, "seen": seen.get(key, 1)})
    decision_due = [r["key"] for r in rows if r["seen"] >= 2 and r["state"] in ("still-open", "vanished")]
    return {
        "previous_report": str(latest) if latest else None,
        "previous_has_index": latest_index is not None,
        "earlier": rows,
        "decision_due": decision_due,
    }


def dated_lines_after(paths, after):
    n = 0
    for p in paths:
        for line in read(p).splitlines():
            ds = DATE.findall(line)
            if ds and (after is None or max(ds) > after):
                n += 1
    return n


def deep_checks(repo, rc, orders, mem_dir):
    why = {}  # check -> reasons; two reasons for one check are ONE recommendation

    def say(check, reason):
        why.setdefault(check, []).append(reason)

    # kohaerenz-scan/ = the folder before the LA1 rename (2026-08-14); registers written there still count
    regs = sorted([p for d in ("coherence-scan", "kohaerenz-scan")
                   for p in (repo / "docs/research" / d).glob("register-*.md")], key=report_date)
    last_reg = report_date(regs[-1]) if regs else None
    rule_files = [repo / "CLAUDE.md"] + sorted((repo / ".claude/rules").glob("*.md"))
    n = dated_lines_after([p for p in rule_files if p.is_file()], last_reg)
    if n >= NEW_RULES_MIN:
        since = f"since the last coherence register ({last_reg})" if last_reg else "and no coherence register yet"
        say("coherence-scan", f"{n} new dated rule lines {since}")
    recurring = [r for r in rc["earlier"] if r["seen"] >= 3 and r["state"] in ("still-open", "vanished")]
    if recurring:
        say("coherence-scan", f"{len(recurring)} finding(s) came back a third time without a fix "
                              f"({', '.join(r['key'] for r in recurring[:3])}) — the source keeps producing them")
    idx = mem_dir / "MEMORY.md"
    if idx.is_file():
        raw = idx.read_bytes()
        nl = raw.count(b"\n") + (0 if raw.endswith(b"\n") or not raw else 1)
        if nl >= MEM_LINES * MEM_NEAR or len(raw) >= MEM_BYTES * MEM_NEAR:
            say("memory-dream", f"memory index at {nl}/{MEM_LINES} lines, {len(raw)}/{MEM_BYTES} bytes")
    ahead = [e for e in orders if not e["checked"] and "rebuild-ahead" in e["text"]]
    if ahead:
        say("full-audit", f"the order list announces a structural rebuild ({title_of(ahead[0])})")
    return [f"deep check suggested: {c} — {'; '.join(r)} — measured price on the proving brain: "
            f"~{PRICE[c]}M tokens per run (brain-scan ~{PRICE['brain-scan']}M)" for c, r in why.items()]


# ── machine checks ─────────────────────────────────────────────────────────
def run(cmd, cwd, timeout):
    try:
        p = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=timeout)
        return p.returncode, p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        return None, f"timeout after {timeout}s"
    except OSError as e:
        return None, str(e)


def F(sev, title, state=None):
    f = {"severity": sev, "title": title[:400]}
    if state:
        f["state"] = state
    return f


def crash(name, rc, out):
    tail = " ".join(out.strip().splitlines()[-2:])[:200]
    return F("P1", f"{name} did not complete (rc={rc}): {tail} — a crash, not a finding about the brain")


def map_effect(rc, out, skip_e6):
    rows = re.findall(r"^(OK|ROT|WARN|INFO)\s+(E\d+)\s+(.*)$", out, re.M)
    if rc not in (0, 1) or not rows:
        return [crash("effect-check.sh", rc, out)]
    res, ok = [], []
    for kind, eid, rest in rows:
        if skip_e6 and eid == "E6":
            continue
        if kind == "OK":
            ok.append(eid)
        else:
            res.append(F({"ROT": "P1", "WARN": "P2", "INFO": "INFO"}[kind], f"effect-check {eid}: {rest.strip()}"))
    if ok:
        res.append(F("OK", f"effect-check {', '.join(ok)} green", "verified"))
    return res


def map_invariants(rc, out):
    if rc not in (0, 1):
        return [crash("invariant-check.py", rc, out)]
    drift = [l.strip() for l in out.splitlines() if re.search(r"NEW site:|drift:|vanished:|search failed:", l)]
    due = len(re.findall(r"MECHANISM due", out))
    res = [F("P1", f"invariant register drift ({len(drift)} line(s)): {'; '.join(drift[:3])}")] if drift else []
    if due:
        res.append(F("P2", f"invariant register: {due} class(es) with a MECHANISM due — they have no other reader"))
    if not res:
        res.append(F("OK", "invariant-check: no drift, no mechanism due", "verified"))
    return res


def map_selftest(rc, out):
    if rc == 0:
        return [F("OK", "brain-selftest: everything that has a proof passed it", "verified")]
    if rc == 1 and "SELF-TEST: FAILURE" in out:
        bad = [l.strip() for l in out.splitlines() if l.strip().startswith(("!!", "FAIL"))]
        return [F("P1", f"brain-selftest failed: {'; '.join(bad[:4]) or 'see the self-test output'}")]
    return [crash("brain-selftest.sh", rc, out)]


def map_lines(name, rc, out, loud_prefix, summary_prefix, sev):
    if rc != 0:
        return [crash(name, rc, out)]
    lines = [l.strip() for l in out.splitlines() if l.strip()]
    summ = [l for l in lines if l.startswith(summary_prefix)]
    hits = [l for l in lines if l.startswith(loud_prefix)]
    res = [F(sev, f"{name}: {h[:300]}") for h in hits[:10]]
    if len(hits) > 10:
        res.append(F(sev, f"{name}: {len(hits) - 10} more line(s) of the same kind"))
    if not hits:
        res.append(F("OK", f"{name}: {summ[-1] if summ else 'nothing to report'}", "verified"))
    return res


def machine(repo, core, last_date, today):
    py = sys.executable or "python3"
    bash = shutil.which("bash") or "bash"
    S = core / "scripts"
    days = 14
    if last_date:
        try:
            days = max(1, (datetime.date.fromisoformat(today) - datetime.date.fromisoformat(last_date)).days)
        except ValueError:
            pass
    register = repo / "docs/maintenance/invariants.md"
    jobs = {
        "effect-check.sh": ([bash, str(S / "effect-check.sh"), str(repo)], 120),
        "invariant-check.py": ([py, str(S / "invariant-check.py"), str(register)], 180),
        "brain-selftest.sh": ([bash, str(S / "brain-selftest.sh"), str(repo)], 420),
        "local-machinery.py": ([py, str(S / "local-machinery.py"), "--repo", str(repo)], 120),
        "commitments.py": ([py, str(S / "commitments.py"), "--repo", str(repo), "--days", str(days)], 120),
    }
    missing = [n for n in jobs if not (S / n).is_file()]
    findings = []
    if not register.is_file() and "invariant-check.py" not in missing:
        findings.append(F("INFO", "no invariant register at docs/maintenance/invariants.md — section not executed"))
        jobs.pop("invariant-check.py")
    run_jobs = {n: j for n, j in jobs.items() if n not in missing}
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as ex:
        futs = {n: ex.submit(run, cmd, repo, t) for n, (cmd, t) in run_jobs.items()}
        out = {n: f.result() for n, f in futs.items()}
    if "effect-check.sh" in out:
        findings += map_effect(*out["effect-check.sh"], skip_e6="commitments.py" in out)
    if "invariant-check.py" in out:
        findings += map_invariants(*out["invariant-check.py"])
    if "brain-selftest.sh" in out:
        findings += map_selftest(*out["brain-selftest.sh"])
    if "local-machinery.py" in out:
        findings += map_lines("local-machinery", *out["local-machinery.py"], "!!", "local machinery summary:", "P1")
    if "commitments.py" in out:
        findings += map_lines("commitments", *out["commitments.py"], "loose commitment", "commitments summary:", "P2")
    if missing:
        findings.append(F("INFO", f"not available in this core checkout: {', '.join(missing)}"))
    return findings, sorted(run_jobs)


def render(rc, deep, orders_open):
    st = {}
    for r in rc["earlier"]:
        st[r["state"]] = st.get(r["state"], 0) + 1
    L = ["## Return channel (what became of the last run's findings)", ""]
    if not rc["previous_report"]:
        L.append("No earlier report — nothing to trace back.")
    elif not rc["previous_has_index"]:
        L.append(f"The previous report ({Path(rc['previous_report']).name}) has no finding index — "
                 "its findings cannot be traced; tracing starts with this run.")
    else:
        L.append(f"Previous report {Path(rc['previous_report']).name}: {len(rc['earlier'])} finding(s) — "
                 + ", ".join(f"{k} {v}" for k, v in sorted(st.items())))
        L.append("")
        for r in rc["earlier"]:
            L.append(f"- {r['state']}: `{r['key']}` ({r['severity']}, exit was {r['exit']}, seen {r['seen']}x) — {r['title']}")
        if rc["decision_due"]:
            L += ["", "Seen twice without a fix — if this run finds them again they are operator decisions, "
                      "not findings: " + ", ".join(f"`{k}`" for k in rc["decision_due"])]
    L += ["", "## Ordered items (not executed by the scan — fixing happens in the session)", ""]
    L += [f"- {title_of(e)}" for e in orders_open] or ["None open."]
    L += ["", "## Deep check", ""]
    L += deep or ["No deep check suggested."]
    return "\n".join(L) + "\n\n"


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--out", required=True)
    ap.add_argument("--today", default=datetime.date.today().isoformat())
    ap.add_argument("--core", default=str(Path(__file__).resolve().parent.parent))
    ap.add_argument("--memory-dir")
    ap.add_argument("--skip-machine", action="store_true")
    a = ap.parse_args(argv)
    repo, out, core = Path(a.repo).resolve(), Path(a.out), Path(a.core).resolve()
    out.mkdir(parents=True, exist_ok=True)
    mem = Path(a.memory_dir) if a.memory_dir else (
        Path.home() / ".claude/projects" / re.sub(r"[^A-Za-z0-9]", "-", str(repo)) / "memory")
    data = {}
    try:
        data = json.loads(read(repo / ".claude/rules/brain-scan-prep.json") or "{}")
    except ValueError:
        pass
    markers = {"decided": DECIDED + data.get("decided", []), "dropped": DROPPED + data.get("dropped", [])}

    reports = sorted((p for p in (repo / "docs/research/brain-scan").glob("scan-*.md")
                      if report_date(p) and report_date(p) < a.today), key=report_date)
    orders = parse_orders(read(repo / "docs/maintenance/brain-scan-auftraege.md"))
    rc = return_channel(reports, orders, markers)
    last_date = report_date(reports[-1]) if reports else None
    deep = deep_checks(repo, rc, orders, mem)
    oo = ordered_open(orders)
    findings, ran = ([], []) if a.skip_machine else machine(repo, core, last_date, a.today)

    rc_out = dict(rc, deep_check=deep, ordered_open=[title_of(e) for e in oo], last_scan_date=last_date)
    with open(out / "return-channel.json", "w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(rc_out, indent=1, ensure_ascii=False) + "\n")
    with open(out / "scan-machine.json", "w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(
            {"section": "machine", "summary": f"deterministic checks run: {', '.join(ran) or 'none'}",
             "findings": findings}, indent=1, ensure_ascii=False) + "\n")
    with open(out / "report-machine.md", "w", encoding="utf-8", newline="\n") as fh:
        fh.write(render(rc, deep, oo))

    states = {s: sum(1 for r in rc["earlier"] if r["state"] == s)
              for s in ("done", "decided", "dropped", "still-open", "vanished")}
    for l in deep:
        print(l)
    summary = {
        "return_channel": str(out / "return-channel.json"),
        "machine_file": str(out / "scan-machine.json"),
        "report_head": str(out / "report-machine.md"),
        "last_scan_date": last_date,
        "earlier": len(rc["earlier"]), "states": states,
        "decision_due": rc["decision_due"],
        "deep_check": deep,
        "ordered_open": len(oo),
        "machine_findings": len(findings),
        "machine_ok": sum(1 for f in findings if f["severity"] == "OK"),
        "machine_p0": sum(1 for f in findings if f["severity"] == "P0"),
        "machine_p1": sum(1 for f in findings if f["severity"] == "P1"),
    }
    print(json.dumps({"brain_scan_prep": summary}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
