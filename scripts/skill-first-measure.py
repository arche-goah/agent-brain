#!/usr/bin/env python3
"""skill-first-measure — Skill calls per session and Stop-gate firings per turn kind.

WHY: a rule like skill-first ("is there a skill for this? use it") and the Stop gates
that carry other rules are only worth their cost if they change behaviour where it
matters. Two numbers answer that from the transcripts, with no extra logging: how often
sessions actually call the Skill tool, and how often each gate fires — split by whether
the turn was opened by the OPERATOR or by a harness notification (a finished background
task, a watcher event). A gate firing on notification turns interrupts nobody's request
and is the first candidate to sit those turns out.

Two definitions this script must share with the gates, or it measures something else:
- Turn kind is the core's (helpers/turn-kind.cjs, `isNotification`): a user record is a
  notification only if it carries a `<task-notification>` frame and NOTHING but harness
  frames (`<system-reminder>`, `<task-notification>`); a frame plus one word of the
  operator is an operator record. Mirrored below; the fixture checks parity with the
  helper whenever it is present.
- Every gate tag in a Stop-hook feedback block counts. The dispatcher folds several
  checks into ONE block — counting the first tag only hid whole gates (measured on the
  proving instance: 39 counted where 48 had fired).

Usage:
  skill-first-measure.py [--dir PATH] [--since YYYY-MM-DD] [--until YYYY-MM-DD]

  --dir     transcript directory; default derived from BRAIN_DIR / cwd like
            transcript-recall.py (never hardcode an instance path)
  a session counts when its FIRST record falls inside [--since, --until]

Prints one JSON object (stdout pinned UTF-8/LF). Exit 0 · 2 = no transcript directory.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import Counter
from pathlib import Path

_INSTANCE = Path(os.environ.get("BRAIN_DIR", Path.cwd())).resolve()
DIR_DEFAULT = Path.home() / ".claude/projects" / re.sub(r"[^A-Za-z0-9]", "-", str(_INSTANCE))

# helpers/turn-kind.cjs, verbatim in meaning: keep both in step.
FRAMES = re.compile(r"<system-reminder>[\s\S]*?</system-reminder>|<task-notification>[\s\S]*?</task-notification>")
GATE_TAG = re.compile(r"\[([A-Z][A-Z0-9-]*(?:GATE|VERIFIER))\]")
STOP_FEEDBACK = "Stop hook feedback"


def is_notification(text) -> bool:
    return isinstance(text, str) and "<task-notification>" in text and not FRAMES.sub("", text).strip()


def measure(directory: Path, since: str, until: str) -> dict:
    sessions = skill = fires = on_notif = 0
    per_gate, per_gate_notif = Counter(), Counter()
    for f in sorted(directory.glob("*.jsonl")):
        recs = []
        with open(f, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    r = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(r, dict):
                    recs.append(r)
        stamps = [r["timestamp"] for r in recs if isinstance(r.get("timestamp"), str)]
        if not stamps or not (since <= min(stamps)[:10] <= until):
            continue
        sessions += 1
        prev_user = None  # the record that opened the turn the gate fired on
        for r in recs:
            c = (r.get("message") or {}).get("content")
            if r.get("type") == "assistant" and isinstance(c, list):
                skill += sum(1 for b in c if isinstance(b, dict)
                             and b.get("type") == "tool_use" and b.get("name") == "Skill")
            if r.get("type") != "user" or not isinstance(c, str):
                continue  # tool results arrive as lists and open no turn
            if c.startswith(STOP_FEEDBACK):
                fires += 1
                notif = prev_user is not None and is_notification(prev_user)
                on_notif += notif
                for g in sorted(set(GATE_TAG.findall(c))) or ["untagged"]:
                    per_gate[g] += 1
                    per_gate_notif[g] += notif
            else:
                prev_user = c
    n = max(sessions, 1)
    return {"sessions": sessions, "skill_calls": skill, "skill_per_session": round(skill / n, 2),
            "stop_fires": fires, "fires_per_session": round(fires / n, 2),
            "on_notification_turns": on_notif, "per_gate": dict(sorted(per_gate.items())),
            "per_gate_on_notification": {g: k for g, k in sorted(per_gate_notif.items()) if k}}


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")  # OS-9: the JSON is parsed
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dir", default=str(DIR_DEFAULT))
    ap.add_argument("--since", default="0000-00-00")
    ap.add_argument("--until", default="9999-99-99")
    a = ap.parse_args()
    d = Path(a.dir)
    if not d.is_dir():
        print(f"no transcript directory: {d.as_posix()}", file=sys.stderr)
        return 2
    print(json.dumps(measure(d, a.since, a.until), indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
