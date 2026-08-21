#!/usr/bin/env python3
"""transcript-recall — find what earlier sessions already read, before reading it live again.

WHY (Windows instance, 2026-08-21): a session's live research of a reference showfile
was "lost" and partly redone live — until someone grepped the transcript of the previous
session and found the complete analysis in minutes. The transcripts are layer 1 of the
session traceability doctrine (rules/working-rules.md) and are ALWAYS there; what was
missing was a one-command way to ask them. This is that command. Read-only, stdlib only,
OS-agnostic.

Usage:
  transcript-recall.py <keyword> [<keyword> ...] [--all] [--days N] [--limit N]
                       [--session ID] [--dir PATH] [--json]

  keywords   case-insensitive; ALL must match a line (use --all) or ANY (default)
  --days N   only transcripts touched in the last N days (default 14)
  --limit N  snippets per session (default 5)
  --session  restrict to one session id (from a commit trailer `Claude-Session:` or a
             memory file's `originSessionId`)
  --dir      transcript directory (default: derived from BRAIN_DIR / cwd the same way
             memory-lint.py derives the memory dir — never hardcode an instance path)
  --json     machine-readable

Exit 0 = hits, 1 = no hits, 2 = no transcript dir.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

_INSTANCE = Path(os.environ.get("BRAIN_DIR", Path.cwd())).resolve()
DIR_DEFAULT = Path.home() / ".claude/projects" / re.sub(r"[^A-Za-z0-9]", "-", str(_INSTANCE))


def text_of(obj) -> str:
    """Flatten one transcript line into searchable text: message text, tool names,
    tool inputs, tool results. Keeps it cheap — no pretty printing."""
    msg = obj.get("message") if isinstance(obj, dict) else None
    if not isinstance(msg, dict):
        return ""
    parts = []
    c = msg.get("content")
    if isinstance(c, str):
        parts.append(c)
    elif isinstance(c, list):
        for b in c:
            if not isinstance(b, dict):
                continue
            t = b.get("type")
            if t == "text":
                parts.append(str(b.get("text", "")))
            elif t == "tool_use":
                parts.append(f"[tool_use {b.get('name')}] {json.dumps(b.get('input', {}), ensure_ascii=False)[:2000]}")
            elif t == "tool_result":
                cc = b.get("content")
                if isinstance(cc, str):
                    parts.append(f"[tool_result] {cc}")
                elif isinstance(cc, list):
                    parts.append("[tool_result] " + " ".join(str(x.get("text", "")) for x in cc if isinstance(x, dict)))
    return "\n".join(parts)


def snippet(text: str, pat: re.Pattern, width: int = 90) -> str:
    m = pat.search(text)
    if not m:
        return text[:width * 2].replace("\n", " ")
    a, b = max(0, m.start() - width), min(len(text), m.end() + width)
    return ("…" if a else "") + text[a:b].replace("\n", " ") + ("…" if b < len(text) else "")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("keywords", nargs="+")
    ap.add_argument("--all", action="store_true", help="all keywords must match")
    ap.add_argument("--days", type=float, default=14)
    ap.add_argument("--limit", type=int, default=5)
    ap.add_argument("--session")
    ap.add_argument("--dir")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    tdir = Path(a.dir) if a.dir else DIR_DEFAULT
    if not tdir.is_dir():
        print(f"transcript-recall: no transcript dir at {tdir}", file=sys.stderr)
        return 2
    pats = [re.compile(re.escape(k), re.I) for k in a.keywords]
    any_pat = re.compile("|".join(re.escape(k) for k in a.keywords), re.I)
    cutoff = time.time() - a.days * 86400
    files = sorted((p for p in tdir.glob("*.jsonl")
                    if p.stat().st_mtime >= cutoff and (not a.session or p.stem == a.session)),
                   key=lambda p: p.stat().st_mtime, reverse=True)

    sessions = []
    for p in files:
        hits, first, last, n_lines = [], None, None, 0
        with p.open(encoding="utf-8", errors="replace") as fh:
            for line in fh:
                n_lines += 1
                try:
                    obj = json.loads(line)
                except ValueError:
                    continue
                ts = obj.get("timestamp") if isinstance(obj, dict) else None
                if ts:
                    first = first or ts
                    last = ts
                txt = text_of(obj)
                if not txt:
                    continue
                ok = all(pt.search(txt) for pt in pats) if a.all else any_pat.search(txt)
                if not ok:
                    continue
                role = (obj.get("message") or {}).get("role", "?")
                hits.append({"ts": ts, "role": role, "snippet": snippet(txt, any_pat)})
        if hits:
            sessions.append({"session": p.stem, "file": str(p), "first": first, "last": last,
                             "hits": len(hits), "samples": hits[: a.limit]})

    if a.json:
        print(json.dumps({"dir": str(tdir), "keywords": a.keywords, "sessions": sessions},
                         ensure_ascii=False, indent=1))
        return 0 if sessions else 1
    if not sessions:
        print(f"transcript-recall: no hits for {a.keywords} in {len(files)} transcript(s) "
              f"(last {a.days:g} days, {tdir})")
        return 1
    total = sum(s["hits"] for s in sessions)
    print(f"transcript-recall: {total} hit(s) in {len(sessions)} session(s) for {a.keywords}")
    for s in sessions:
        print(f"\n== {s['session']}  {s['first']} .. {s['last']}  ({s['hits']} hits)")
        for h in s["samples"]:
            print(f"  [{(h['ts'] or '')[:16]} {h['role']}] {h['snippet']}")
        if s["hits"] > len(s["samples"]):
            print(f"  … {s['hits'] - len(s['samples'])} more — narrow with --session {s['session']} or --all")
    return 0


if __name__ == "__main__":
    sys.exit(main())
