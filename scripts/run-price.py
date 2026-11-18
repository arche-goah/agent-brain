#!/usr/bin/env python3
"""Measured price of a deep check: median tokens per workflow run, read from this machine's own run records.

WHY (audit-audit on the Windows instance, 2026-11-10, finding AA-8; released by the core owner the same day): the
rule text and the brain-scan head named fixed prices measured once on one brain in 2026-08/10 (coherence-scan
~2.6M). On the Windows instance the same scan had grown to 2.7 -> 3.8 -> 5.7M tokens in 19 days, so every proposal
"run it, it costs about ..." quoted half the real price. The run records already hold the number; this script reads
it instead of a remembered constant.

What one run costs here: `totalTokens` of its record (<project>/<session>/workflows/wf_*.json), PLUS the tokens of
an earlier attempt when the run was resumed. A resume rewrites the record with the resumed part only (measured
2026-10-12: record 1.15M, agent transcripts 2.73M, -58 %); the agent transcripts of the earlier attempt still lie in
<project>/<session>/subagents/workflows/<runId>/ and finished before the record's `startTime`. Their usage
(input + cache creation + output, each message once) is added. Failed runs count: they spent the tokens too.

  run-price.py [--repo DIR | --project-dir DIR] [--json] [NAME ...]

--repo: the brain whose records to read (default: cwd); its record dir is ~/.claude/projects/<path, every
non-alphanumeric character as "-">. --project-dir names that dir directly. NAME limits the output to workflows.
No record for a workflow = the fallback price below, marked as such. Exit 0 always (a price is advice, not a gate).
"""
import argparse
import json
import re
import statistics
import sys
import time
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    sys.stderr.reconfigure(encoding="utf-8")  # OS-9 stderr half (#524)
except (AttributeError, ValueError):
    pass

# Measured on one brain, 2026-08/10 (rules/intelligence.md before this script). Only a fallback: a workflow
# without a record on this machine is quoted with these, said as "fallback".
FALLBACK = {"brain-scan": 1.5, "memory-dream": 0.6, "coherence-scan": 2.6, "full-audit": 6.0, "audit-audit": 1.4}


def record_dir(repo):
    return Path.home() / ".claude" / "projects" / re.sub(r"[^A-Za-z0-9]", "-", str(Path(repo).resolve()))


def transcript_tokens(path):
    """input + cache creation + output of every assistant message in one agent transcript, each message id once."""
    seen, n = set(), 0
    try:
        fh = path.open(encoding="utf-8", errors="replace")
    except OSError:
        return 0
    with fh:
        for line in fh:
            if '"usage"' not in line:
                continue
            try:
                r = json.loads(line)
            except ValueError:
                continue
            m = r.get("message") or {}
            u = m.get("usage")
            if r.get("type") != "assistant" or not isinstance(u, dict) or m.get("id") in seen:
                continue
            seen.add(m.get("id"))
            n += sum(int(u.get(k) or 0) for k in ("input_tokens", "cache_creation_input_tokens", "output_tokens"))
    return n


def earlier_attempt(session_dir, run_id, start_ms):
    """Tokens of the agents that finished before the record's start: the attempt a resume replaced."""
    if not start_ms:
        return 0
    adir = session_dir / "subagents" / "workflows" / run_id
    total = 0
    for a in sorted(adir.glob("agent-*.jsonl")):
        try:
            if a.stat().st_mtime * 1000 < start_ms:
                total += transcript_tokens(a)
        except OSError:
            continue
    return total


def runs(project_dir):
    """Every run record of the project dir: [{name, status, date, tokens, resumed_add}]."""
    out = []
    for rec_path in sorted(Path(project_dir).glob("*/workflows/wf_*.json")):
        try:
            rec = json.loads(rec_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        name, tokens = rec.get("workflowName"), rec.get("totalTokens")
        if not name or not isinstance(tokens, (int, float)) or tokens <= 0:
            continue
        add = earlier_attempt(rec_path.parent.parent, str(rec.get("runId") or rec_path.stem), rec.get("startTime"))
        out.append({"name": name, "status": rec.get("status"), "date": str(rec.get("timestamp") or "")[:10],
                    "tokens": int(tokens) + add, "resumed_add": add})
    return out


def prices(project_dir):
    """{name: {median, n, first, last, resumed, statuses}} over every record of the dir."""
    by = {}
    for r in runs(project_dir):
        by.setdefault(r["name"], []).append(r)
    res = {}
    for name, rs in by.items():
        dates = sorted(r["date"] for r in rs if r["date"])
        st = {}
        for r in rs:
            st[r["status"]] = st.get(r["status"], 0) + 1
        res[name] = {"median": int(statistics.median(r["tokens"] for r in rs)), "n": len(rs),
                     "first": dates[0] if dates else "", "last": dates[-1] if dates else "",
                     "resumed": sum(1 for r in rs if r["resumed_add"]), "statuses": st}
    return res


def millions(n):
    return f"~{n / 1e6:.1f}M"


def price_line(name, p):
    """One line per workflow, the form the rule and the brain-scan head quote."""
    if p:
        extra = f", {p['resumed']} resumed (earlier attempt added)" if p["resumed"] else ""
        return (f"{name}: {millions(p['median'])} tokens per run, median of {p['n']} run(s) on this machine "
                f"({p['first']} .. {p['last']}{extra})")
    if name in FALLBACK:
        return f"{name}: ~{FALLBACK[name]}M tokens per run, fallback (no run record on this machine)"
    return f"{name}: no run record on this machine and no fallback price"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--repo", default=".")
    ap.add_argument("--project-dir")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("names", nargs="*")
    a = ap.parse_args(argv)
    pdir = Path(a.project_dir) if a.project_dir else record_dir(a.repo)
    ps = prices(pdir) if pdir.is_dir() else {}
    names = a.names or sorted(set(FALLBACK) | set(ps))
    if a.json:
        print(json.dumps({n: ps.get(n) or ({"fallback": FALLBACK[n]} if n in FALLBACK else None) for n in names},
                         ensure_ascii=False))
        return 0
    print(f"run records: {pdir} ({'read' if pdir.is_dir() else 'not found'}, {time.strftime('%Y-%m-%d')})")
    for n in names:
        print(price_line(n, ps.get(n)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
