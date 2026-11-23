#!/usr/bin/env python3
"""gate-health: count gate MALFUNCTIONS (a hook refusal that is no decision - it timed out or crashed) per gate over
this brain's recent session transcripts, and name a gate that malfunctions in two or more sessions.

WHY (measured 2026-11-23 on the macOS instance, 60 newest transcripts): content-review-gate timed out 37 times in 15
sessions; no reply named a cause, and nothing outside the turn noticed - each session saw one retry that passed. The
operator (translated): "detecting faults on your own ... is the goal". This is the detection that does not depend on
the agent: the session start runs it. The form of a malfunction lives in ONE file, gate-malfunction.json at the core
root (also read by helpers/root-cause-gate.cjs).

Usage: gate-health.py [--root <brain>] [--days 14] [--min-sessions 2] [--dir <transcript folder>] [--all]
  prints one line per gate at or over --min-sessions ("gate-health: content-review-gate timed out 37x in 15 sessions
  (last 14 days)"), nothing when all is quiet; --all lists every gate. Exit 0 always (a report, not a gate).
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent


def data():
    d = json.loads((HERE.parent / "gate-malfunction.json").read_text(encoding="utf-8"))
    return re.compile(d["refusal"]), re.compile("|".join(d["malfunction"])), re.compile(d["gate"])


def transcript_dir(root: str) -> Path:
    cfg = Path(os.environ.get("CLAUDE_CONFIG_DIR") or (Path.home() / ".claude"))
    return cfg / "projects" / re.sub(r"[^A-Za-z0-9]", "-", str(Path(root).resolve()))


def results(line: str):
    """The error texts of tool results in one transcript line."""
    if '"is_error":true' not in line and '"is_error": true' not in line:
        return []
    try:
        rec = json.loads(line)
    except ValueError:
        return []
    content = (rec.get("message") or {}).get("content")
    out = []
    for b in content if isinstance(content, list) else []:
        if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("is_error"):
            c = b.get("content")
            out.append(c if isinstance(c, str) else " ".join(x.get("text", "") for x in c or [] if isinstance(x, dict)))
    return out


def count(folder: Path, days: float, rx):
    refusal, malf, gate = rx
    since = time.time() - days * 86400
    per = {}
    for f in sorted(folder.glob("*.jsonl")):
        try:
            if f.stat().st_mtime < since:
                continue
            lines = f.open(encoding="utf-8", errors="replace")
        except OSError:
            continue
        with lines:
            for line in lines:
                for t in results(line):
                    t = t.strip()
                    if not refusal.search(t) or not malf.search(t):
                        continue
                    g = gate.search(t)
                    name = (g.group(1) or f"command hook {g.group(2)}") if g else "a hook"
                    what = malf.search(t).group(0).split(";")[0]
                    e = per.setdefault(name, {"n": 0, "sessions": set(), "what": what})
                    e["n"] += 1
                    e["sessions"].add(f.stem)
    return per


def main(argv):
    def opt(k, d):
        return argv[argv.index(k) + 1] if k in argv and argv.index(k) + 1 < len(argv) else d
    root = opt("--root", os.environ.get("CLAUDE_PROJECT_DIR", "."))
    days = float(opt("--days", "14"))
    least = int(opt("--min-sessions", "2"))
    folder = Path(opt("--dir", "")) if "--dir" in argv else transcript_dir(root)
    try:
        rx = data()
    except (OSError, ValueError, KeyError) as e:
        print(f"gate-health: gate-malfunction.json unreadable ({e}) - NOT checked")
        return 0
    per = count(folder, days, rx)
    for name, e in sorted(per.items(), key=lambda kv: -kv[1]["n"]):
        if "--all" in argv or len(e["sessions"]) >= least:
            print(f"gate-health: {name} {e['what']} {e['n']}x in {len(e['sessions'])} session(s) (last {days:g} days) - "
                  "a malfunction is no decision: measure why (its run time, what it read), fix it at the gate")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
