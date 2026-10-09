#!/usr/bin/env python3
"""transcript-latency — latency and workload per day, measured from session transcripts.

WHY: "the brain got slower" after a rebuild (more hooks, more rules, more gates) is a
claim, and the transcripts already hold the measurement — every record is timestamped.
This reads them and splits each turn into tool time and model time, so a before/after
comparison says WHERE the time went instead of how it felt. Measured on the proving
instance: a rebuild that "felt slower" slowed no single step; each answer simply did
more (more tool calls per turn) — a different fix than the one the feeling suggested.

Per local calendar day:
  1. turn duration (operator prompt -> last assistant/tool event), split into tool time
     (tool_use -> tool_result) and model time (the rest)
  2. tool calls per turn
  3. call latency per tool family (an MCP server name, or the tool name)
  4. assistant output volume (text + thinking characters)

A turn starts at a user record that is neither meta nor a tool result. Main-session
transcripts only (top-level *.jsonl); subagent transcripts are not turns of the operator.

Usage:
  transcript-latency.py [--since YYYY-MM-DD] [--family NAME ...] [--top N]
                        [--dir PATH] [--json]

  --family   report this family (repeatable); default: the --top N most-called (5)
  --dir      transcript directory; default derived from BRAIN_DIR / cwd the same way
             transcript-recall.py does it (never hardcode an instance path)

Exit 0 = report printed · 2 = no transcript directory.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

_INSTANCE = Path(os.environ.get("BRAIN_DIR", Path.cwd())).resolve()
DIR_DEFAULT = Path.home() / ".claude/projects" / re.sub(r"[^A-Za-z0-9]", "-", str(_INSTANCE))


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def day(t):
    return datetime.fromtimestamp(t).strftime("%Y-%m-%d")  # local day, everywhere


def med(xs):
    xs = sorted(xs)
    return xs[len(xs) // 2] if xs else float("nan")


def p90(xs):
    xs = sorted(xs)
    return xs[min(int(len(xs) * 0.9), len(xs) - 1)] if xs else float("nan")


def family(name):
    return name.split("__")[1] if name.startswith("mcp__") and name.count("__") >= 2 else name


def measure(directory: Path):
    turns = defaultdict(list)      # day -> [(duration, tool_time, n_tools)]
    tool_lat = defaultdict(list)   # (day, family) -> [seconds]
    out_chars = Counter()          # day -> chars of assistant text + thinking
    for f in sorted(directory.glob("*.jsonl")):
        events = []
        with open(f, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    e = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(e, dict) and "timestamp" in e:
                    events.append(e)
        events.sort(key=lambda e: e["timestamp"])
        pending = {}   # tool_use_id -> (t, family)
        cur = None     # [start, last, tool_time, n_tools]

        def close():
            nonlocal cur
            if cur and cur[1] and cur[1] > cur[0]:
                turns[day(cur[0])].append((cur[1] - cur[0], cur[2], cur[3]))
            cur = None

        for e in events:
            t = ts(e["timestamp"])
            typ = e.get("type")
            content = (e.get("message") or {}).get("content")
            if isinstance(content, str):
                content = [{"type": "text", "text": content}]
            blocks = [b for b in content if isinstance(b, dict)] if isinstance(content, list) else []
            has_result = any(b.get("type") == "tool_result" for b in blocks)

            if typ == "user" and not e.get("isMeta") and not has_result:
                close()
                cur = [t, None, 0.0, 0]
                continue
            if typ == "assistant":
                if cur:
                    cur[1] = t
                for b in blocks:
                    if b.get("type") == "tool_use":
                        pending[b.get("id")] = (t, family(b.get("name", "?")))
                        if cur:
                            cur[3] += 1
                    elif b.get("type") in ("text", "thinking"):
                        out_chars[day(t)] += len(b.get("text") or b.get("thinking") or "")
            if typ == "user" and has_result:
                if cur:
                    cur[1] = t
                for b in blocks:
                    if b.get("type") == "tool_result":
                        hit = pending.pop(b.get("tool_use_id"), None)
                        if hit:
                            t0, fam = hit
                            tool_lat[(day(t0), fam)].append(t - t0)
                            if cur:
                                cur[2] += t - t0
        close()
    return turns, tool_lat, out_chars


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")  # OS-9: --json is parsed
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--since", default="0000-00-00")
    ap.add_argument("--family", action="append", help="tool family to report (repeatable)")
    ap.add_argument("--top", type=int, default=5, help="default families: the N most-called")
    ap.add_argument("--dir", default=str(DIR_DEFAULT))
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    directory = Path(args.dir)
    if not directory.is_dir():
        print(f"no transcript directory: {directory.as_posix()}", file=sys.stderr)
        return 2
    turns, tool_lat, out_chars = measure(directory)
    dates = sorted(d for d in turns if d >= args.since)
    calls = Counter()
    for (d, fam), xs in tool_lat.items():
        if d >= args.since:
            calls[fam] += len(xs)
    families = args.family or [f for f, _ in calls.most_common(args.top)]

    report = {"days": {}, "families": {}}
    for d in dates:
        rows = turns[d]
        durs = [r[0] for r in rows]
        report["days"][d] = {"turns": len(rows), "med_s": med(durs), "p90_s": p90(durs),
                             "med_tool_s": med([r[1] for r in rows]),
                             "med_model_s": med([r[0] - r[1] for r in rows]),
                             "med_tools": med([r[2] for r in rows]),
                             "out_kchars": out_chars.get(d, 0) // 1000}
    for fam in families:
        report["families"][fam] = {d: {"n": len(xs), "med_s": med(xs), "p90_s": p90(xs)}
                                   for d in dates if (xs := tool_lat.get((d, fam)))}
    if args.json:
        print(json.dumps(report, indent=1))
        return 0

    print("== turn duration per day (operator prompt -> last event) ==")
    print(f"{'date':<12}{'n':>5}{'med s':>8}{'p90 s':>8}{'med tool-s':>11}"
          f"{'med model-s':>12}{'med tools':>10}{'out kchars':>11}")
    for d, r in report["days"].items():
        print(f"{d:<12}{r['turns']:>5}{r['med_s']:>8.0f}{r['p90_s']:>8.0f}{r['med_tool_s']:>11.0f}"
              f"{r['med_model_s']:>12.0f}{r['med_tools']:>10}{r['out_kchars']:>11}")
    for fam, per_day in report["families"].items():
        print(f"\n== {fam} latency per day (tool_use -> tool_result) ==")
        print(f"{'date':<12}{'n':>5}{'med s':>8}{'p90 s':>8}")
        for d, r in per_day.items():
            print(f"{d:<12}{r['n']:>5}{r['med_s']:>8.1f}{r['p90_s']:>8.1f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
