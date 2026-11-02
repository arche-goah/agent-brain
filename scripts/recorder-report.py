#!/usr/bin/env python3
"""recorder-report.py — the reader of the stop dispatcher's recorder logs.

WHY (measured 2026-10-23 on a macOS instance, core v2.0.3): `brain-friction.py` reported
PREMISE and PROMISE as write-only, and it was right about more than those two. Every check
the template ships in `mode: record` (premise, promise, recall, absence) appends to
`.claude-state/<marker>.jsonl`, and the template's own comment says "read the log before
switching to block" — but no script, skill or scan ever read one. RECALL and ABSENCE only
escaped the finding because a changelog line, a comment and a fixture named their log file.
A recording check exists to answer one question — would this gate have blocked, how often,
on what? — and a measurement series nobody reads answers nothing.

WHAT IT DOES: reads `.claude/rules/stop-checks.json`, and for every check in `mode: record`
reads its log (current generation plus the rotated `.1.jsonl`), counting the entries inside
the window: entries, sessions, and how many would have blocked (`would_block: true`, where
the recorder writes that field). It judges nothing; the brain-scan
(`scripts/brain-scan-prep.py`) runs it and turns each line into a finding.

Output, one line per recorder, then one summary line:
  `!! <LABEL>: <n> entr(y|ies) in <d> days, <s> session(s), <b> would have blocked - decide: block, keep recording, or unwire`
      when at least one entry in the window would have blocked (the measurement exists);
  `   <LABEL>: ...` otherwise (recording, nothing that would have blocked, or no log yet);
  `recorder report summary: <k> recorder(s), <m> with a decision due`.

Usage: recorder-report.py [--root DIR] [--days N] [--today YYYY-MM-DD]
Exit 0 always — a report, not a verdict.
"""
import argparse
import datetime
import json
import os
import re
import sys
from pathlib import Path

# OS-9: brain-scan-prep.py parses this stdout; pin UTF-8 and LF on every platform.
try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass


def entries(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    yield json.loads(line)
                except ValueError:
                    continue
    except OSError:
        return


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    ap.add_argument("--days", type=int, default=14)
    ap.add_argument("--today", default=datetime.date.today().isoformat())
    a = ap.parse_args(argv)
    since = (datetime.date.fromisoformat(a.today) - datetime.timedelta(days=a.days)).isoformat()
    try:
        with open(os.path.join(a.root, ".claude/rules/stop-checks.json"), encoding="utf-8") as fh:
            checks = json.load(fh).get("checks", [])
    except (OSError, ValueError):
        checks = []
    recorders = [c for c in checks if c.get("mode") == "record" and c.get("marker")]
    due = 0
    for c in recorders:
        # A gate may keep a log of its own (promise-gate: promises.jsonl) — the same
        # detection as brain-friction.py check 3: a .jsonl name literal in the gate's source.
        try:
            with open(os.path.join(a.root, c.get("cmd", "")), encoding="utf-8", errors="ignore") as fh:
                src = fh.read()
        except OSError:
            src = ""
        # Both logs, never one instead of the other (audit-audit 2026-11-02, macOS instance: the
        # dispatcher's promise-gate.jsonl carried 31 would_block:true in 14 days while the report read
        # only the gate's own promises.jsonl and printed 0).
        own = c["marker"].lower() + ".jsonl"
        names = sorted(set(re.findall(r"['\"]([\w.-]+\.jsonl)['\"]", src)) | {own})
        paths = [os.path.join(a.root, ".claude-state", n) for n in names]
        paths = [p[:-len(".jsonl")] + ".1.jsonl" for p in paths] + paths
        rows = [e for p in paths for e in entries(p)
                if str(e.get("at") or e.get("ts") or "")[:10] >= since]
        label = c.get("label") or c["marker"]
        state = Path(a.root) / ".claude-state"
        logs = [n for n in names if (state / n).exists() or (state / (n[:-len(".jsonl")] + ".1.jsonl")).exists()]
        if logs and logs != [own]:
            label += f" (logs {', '.join(logs)})"
        if not logs:
            print(f"   {label}: no log yet - the recorder has never fired")
            continue
        sessions = len({e.get("session") for e in rows})
        head = f"{label}: {len(rows)} entr{'y' if len(rows) == 1 else 'ies'} in {a.days} days, {sessions} session(s), "
        # A log whose entries carry no would_block field cannot say "0 would have blocked" - that zero
        # was one symbol for two states (audit-audit 2026-11-02: time-gate writes `anchored`, the closing
        # classifier `model.*`; both printed 0). Say it cannot count; never a quiet zero.
        # A pure log (mode-log: which mode held when) blocks nothing by design; its row says so.
        if c.get("counts_blocks") is False:
            print(f"   {head}a log - it blocks nothing by design (counts_blocks: false)")
            continue
        if rows and not any("would_block" in e for e in rows):
            due += 1
            print(f"!! {head}blocks NOT countable - no entry carries a would_block field; "
                  "write it in the recorder, or read the log by hand before deciding")
            continue
        blocked = sum(1 for e in rows if e.get("would_block") is True)
        line = head + f"{blocked} would have blocked"
        if blocked:
            due += 1
            print(f"!! {line} - decide: block, keep recording, or unwire")
        else:
            print(f"   {line}")
    print(f"recorder report summary: {len(recorders)} recorder(s), {due} with a decision due")
    return 0


if __name__ == "__main__":
    sys.exit(main())
