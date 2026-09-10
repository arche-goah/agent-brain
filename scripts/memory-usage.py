#!/usr/bin/env python3
"""memory-usage — which memory files do sessions actually open, and did the recall hook
name the right ones?

WHY (proving instance, 2026-09-09): the auto-memory had 135 files and 241 transcripts,
and nobody knew which files any session had ever read. Measured here for the first
time: 53 files never opened, the index line carrying the lesson instead. Relevance
decisions (memory-dream: merge, shrink, archive) need this number — archiving is
relevance-based, never age-based (operator rule 2026-08-30), and "never opened" is a
relevance SIGNAL, not a verdict: a HARD rule works from its index line without the file
ever being opened.

Counts, per memory file, over the instance's transcripts (layer 1 of session
traceability — always there, never edited):
  - opens via the Read tool and via Bash readers (cat/sed/head/tail/grep/less) on a
    memory path; a Write/Edit is NOT an open (creating a file is not recalling it);
  - sessions in which the file was opened, and the date of the last open.

--precision joins `.claude-state/memory-recall.jsonl` (written by helpers/memory-recall.cjs
on every prompt) with the transcripts: of the files the hook NAMED, how many were opened
in the same session (precision); of the files a session OPENED, how many the hook had
named (recall). That is the number the injection is armed on — measure, then arm.

Usage:
  memory-usage.py [--dir TRANSCRIPTS] [--memory MEMDIR] [--state STATEFILE]
                  [--never] [--precision] [--json]

Read-only, stdlib only, OS-agnostic: directories are minted the way memory-lint.py and
transcript-recall.py mint them (instance root -> `[^A-Za-z0-9]` -> `-`), never
hardcoded. Exit 0 always; exit 2 when the transcript directory does not exist.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

_INSTANCE = Path(os.environ.get("BRAIN_DIR", Path.cwd())).resolve()
_CFG = Path(os.environ.get("CLAUDE_CONFIG_DIR") or (Path.home() / ".claude"))
_SLUG = re.sub(r"[^A-Za-z0-9]", "-", str(_INSTANCE))
DIR_DEFAULT = _CFG / "projects" / _SLUG
MEM_DEFAULT = DIR_DEFAULT / "memory"
STATE_DEFAULT = _INSTANCE / ".claude-state" / "memory-recall.jsonl"

MEM_PATH = re.compile(r"memory[\\/]([A-Za-z0-9._-]+\.md)")
READERS = re.compile(r"^\s*(cat|sed|head|tail|grep|less|ugrep)\b")


def opens_in(transcript: Path) -> Counter:
    """Memory files opened in one transcript (Read tool + Bash readers)."""
    found: Counter = Counter()
    try:
        fh = transcript.open(encoding="utf-8", errors="ignore")
    except OSError:
        return found
    with fh:
        for line in fh:
            if "memory" not in line:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            msg = obj.get("message") if isinstance(obj, dict) else None
            content = msg.get("content") if isinstance(msg, dict) else None
            if not isinstance(content, list):
                continue
            for block in content:
                if not (isinstance(block, dict) and block.get("type") == "tool_use"):
                    continue
                inp = block.get("input") or {}
                if block.get("name") == "Read":
                    m = MEM_PATH.search(str(inp.get("file_path", "")))
                    if m:
                        found[m.group(1)] += 1
                elif block.get("name") == "Bash":
                    cmd = str(inp.get("command", ""))
                    if READERS.match(cmd):
                        for name in set(MEM_PATH.findall(cmd)):
                            found[name] += 1
    return found


def scan(tdir: Path) -> dict[str, Counter]:
    """session id -> Counter of opened memory files."""
    out: dict[str, Counter] = {}
    for t in sorted(tdir.glob("*.jsonl")):
        out[t.stem] = opens_in(t)
    return out


def usage_report(per_session: dict[str, Counter], tdir: Path, memdir: Path) -> dict:
    opens: Counter = Counter()
    sessions: Counter = Counter()
    last: dict[str, str] = {}
    for sid, c in per_session.items():
        if not c:
            continue
        stamp = dt.date.fromtimestamp((tdir / f"{sid}.jsonl").stat().st_mtime).isoformat()
        for name, n in c.items():
            opens[name] += n
            sessions[name] += 1
            last[name] = max(last.get(name, stamp), stamp)
    current = sorted(p.name for p in memdir.glob("*.md")) if memdir.exists() else []
    files = [
        {"file": f, "opens": opens.get(f, 0), "sessions": sessions.get(f, 0), "last": last.get(f)}
        for f in current
    ]
    files.sort(key=lambda r: (-r["opens"], r["file"]))
    return {
        "transcripts": len(per_session),
        "files": len(current),
        "never_opened": [r["file"] for r in files if r["opens"] == 0 and r["file"] != "MEMORY.md"],
        "per_file": files,
    }


def precision_report(per_session: dict[str, Counter], state: Path) -> dict:
    named: dict[str, set] = defaultdict(set)   # session -> files the hook named
    n_rec = 0
    if state.exists():
        with state.open(encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                n_rec += 1
                for it in rec.get("files", []) + rec.get("topics", []):
                    named[str(rec.get("session", ""))].add(str(it.get("file", "")))
    tp = fp = fn = 0
    sessions_seen = 0
    for sid, files in named.items():
        opened = set(per_session.get(sid, Counter()))
        if sid not in per_session:
            continue          # a session without a transcript (fixture, manual run) cannot be judged
        sessions_seen += 1
        tp += len(files & opened)
        fp += len(files - opened)
        fn += len(opened - files - {"MEMORY.md"})
    prec = tp / (tp + fp) if tp + fp else None
    rec = tp / (tp + fn) if tp + fn else None
    return {"records": n_rec, "sessions_judged": sessions_seen, "named_and_opened": tp,
            "named_not_opened": fp, "opened_not_named": fn,
            "precision": None if prec is None else round(prec, 3),
            "recall": None if rec is None else round(rec, 3)}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dir", type=Path, default=DIR_DEFAULT, help="transcript directory")
    ap.add_argument("--memory", type=Path, default=MEM_DEFAULT, help="auto-memory directory")
    ap.add_argument("--state", type=Path, default=STATE_DEFAULT, help="memory-recall.jsonl")
    ap.add_argument("--never", action="store_true", help="list only files never opened")
    ap.add_argument("--precision", action="store_true", help="judge the recall hook's log")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    if not a.dir.is_dir():
        print(f"no transcript directory: {a.dir.as_posix()}", file=sys.stderr)
        return 2
    per_session = scan(a.dir)
    report = usage_report(per_session, a.dir, a.memory)
    if a.precision:
        report["precision"] = precision_report(per_session, a.state)
    if a.json:
        print(json.dumps(report, ensure_ascii=False, indent=1))
        return 0
    print(f"transcripts {report['transcripts']} · memory files {report['files']} · "
          f"never opened {len(report['never_opened'])}")
    if a.never:
        for f in report["never_opened"]:
            print(f"  {f}")
    else:
        for r in report["per_file"][:25]:
            print(f"  {r['opens']:4d} opens  {r['sessions']:3d} sessions  {r['last'] or '-':10s}  {r['file']}")
    if a.precision:
        p = report["precision"]
        print(f"recall hook: {p['records']} records, {p['sessions_judged']} sessions judged · "
              f"named+opened {p['named_and_opened']} · named-only {p['named_not_opened']} · "
              f"opened-only {p['opened_not_named']} · precision {p['precision']} · recall {p['recall']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
