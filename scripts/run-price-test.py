#!/usr/bin/env python3
"""Fixture tests for scripts/run-price.py: the median comes from the records, a resume adds its earlier attempt,
and a workflow without a record is quoted as a fallback - each with a neighbour that must not count."""
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "run-price.py"
fails = 0


def check(cond, name):
    global fails
    print(("  OK   " if cond else "  FAIL ") + name)
    if not cond:
        fails += 1


def record(pdir, session, run_id, name, tokens, status="completed", date="2026-11-01", start_ms=None):
    wf = pdir / session / "workflows"
    wf.mkdir(parents=True, exist_ok=True)
    rec = {"runId": run_id, "workflowName": name, "status": status, "timestamp": f"{date}T12:00:00.000Z",
           "totalTokens": tokens}
    if start_ms is not None:
        rec["startTime"] = start_ms
    (wf / f"{run_id}.json").write_text(json.dumps(rec), encoding="utf-8")


def agent(pdir, session, run_id, agent_id, usages, mtime):
    adir = pdir / session / "subagents" / "workflows" / run_id
    adir.mkdir(parents=True, exist_ok=True)
    lines = [json.dumps({"type": "assistant", "message": {"id": mid, "usage": u}}) for mid, u in usages]
    lines.append(json.dumps({"type": "user", "message": {"content": "x"}}))
    p = adir / f"agent-{agent_id}.jsonl"
    p.write_text("\n".join(lines) + "\n", encoding="utf-8")
    os.utime(p, (mtime, mtime))


def run(*args):
    p = subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, encoding="utf-8")
    return p.returncode, p.stdout


with tempfile.TemporaryDirectory() as tmp:
    pdir = Path(tmp) / "proj"
    now = time.time()
    start_ms = int((now - 3600) * 1000)
    U = {"input_tokens": 100000, "cache_creation_input_tokens": 50000, "output_tokens": 50000,
         "cache_read_input_tokens": 9000000}

    # three scans: median of 1.0M / 2.0M / 3.0M is 2.0M; the failed one counts (it spent its tokens)
    record(pdir, "s1", "wf_a", "big-scan", 1000000, date="2026-10-01")
    record(pdir, "s2", "wf_b", "big-scan", 3000000, status="failed", date="2026-10-20")
    record(pdir, "s3", "wf_c", "big-scan", 2000000, date="2026-11-01")
    # resumed run: the record holds 500k (the resumed part); one agent finished before startTime (earlier
    # attempt, 200k without cache reads, one message duplicated) and one after (already in the record)
    record(pdir, "s4", "wf_r", "resumed-scan", 500000, start_ms=start_ms)
    agent(pdir, "s4", "wf_r", "old", [("m1", U), ("m1", U)], now - 7200)
    agent(pdir, "s4", "wf_r", "new", [("m2", U)], now - 60)
    # a record without tokens and a broken record are skipped
    record(pdir, "s5", "wf_z", "big-scan", 0)
    (pdir / "s5" / "workflows" / "wf_broken.json").write_text("{not json", encoding="utf-8")

    rc, out = run("--project-dir", str(pdir), "--json", "big-scan", "resumed-scan", "coherence-scan", "unknown-wf")
    data = json.loads(out)
    big = data["big-scan"]
    check(rc == 0, "exit 0")
    check(big["median"] == 2000000 and big["n"] == 3, "median over three records, failed one included")
    check(big["statuses"] == {"completed": 2, "failed": 1}, "statuses counted (zero-token and broken records skipped)")
    check((big["first"], big["last"]) == ("2026-10-01", "2026-11-01"), "date range from the records")
    rs = data["resumed-scan"]
    check(rs["median"] == 700000, f"resume adds the earlier attempt once, without cache reads (got {rs['median']})")
    check(rs["resumed"] == 1, "the resumed run is marked")
    check(data["coherence-scan"] == {"fallback": 2.6}, "no record: the fallback price, marked as such")
    check(data["unknown-wf"] is None, "no record and no fallback: nothing invented")

    # control: the same resumed record without startTime adds nothing (no way to tell the attempts apart)
    record(pdir, "s4", "wf_r", "resumed-scan", 500000)
    rc, out = run("--project-dir", str(pdir), "--json", "resumed-scan")
    check(json.loads(out)["resumed-scan"]["median"] == 500000, "control: without startTime no attempt is added")

    rc, out = run("--project-dir", str(pdir), "big-scan", "coherence-scan")
    check("big-scan: ~2.0M tokens per run, median of 3 run(s) on this machine (2026-10-01 .. 2026-11-01)" in out,
          "text line names median, count and date range")
    check("coherence-scan: ~2.6M tokens per run, fallback (no run record on this machine)" in out,
          "text line says fallback")

    rc, out = run("--project-dir", str(Path(tmp) / "missing"))
    check(rc == 0 and "not found" in out and "fallback" in out, "missing record dir: fallback for every known workflow")

print(f"\nrun-price: {'FAIL' if fails else 'all passed'} ({fails} failure(s))")
sys.exit(1 if fails else 0)
