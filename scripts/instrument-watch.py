#!/usr/bin/env python3
"""instrument-watch.py — an instrument for an unexplained failure runs until the cause is explained.

WHY (operator order 2026-10-29; incident 2026-10-26 on the macOS instance): a desk application quit
twice; a watcher was armed, then left to expire by the session's own rule "only while working at the
desk". The application quit a third time with no instrument running — the exit data was lost. The
operator: "why did you not restart it?" A Monitor ends after 30 minutes and a session ends; nothing
said that the instrument was still owed while the cause stood open.

Data (instance): `.claude/rules/instruments.json`
  {"instruments": [{"id": "<name>", "match": "<substring of the running command line>",
                    "cause": "<ledger id of the open cause>", "start": "<the command that arms it>"}]}
A cause is open while a registered ledger (`.claude/rules/ledgers.json`) holds `- [ ]` with `id: <cause>`.
Output: one `!!` line per instrument whose cause is open and whose process is not running, with the
command that re-arms it (detached). Silent when every owed instrument runs, or none is owed. A cause
that no ledger names is said too — an instrument tied to nothing is a stale entry. Exit 0 always.

Usage: instrument-watch.py [--repo DIR] [--ps-output FILE]   (--ps-output: fixture seam for the process list)
"""
import argparse
import json
import os
import pathlib
import re
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass

BOX = re.compile(r"^- \[( |x|X)\] ")


def load(p):
    try:
        return json.loads(pathlib.Path(p).read_text(encoding="utf-8"))
    except Exception:
        return {}


def cause_states(repo):
    """{ledger id: True if open, False if ticked} over every registered ledger."""
    out = {}
    for rel in (load(repo / ".claude" / "rules" / "ledgers.json").get("ledgers") or []):
        try:
            lines = (repo / rel).read_text(encoding="utf-8").splitlines()
        except OSError:
            continue
        state = None
        for line in lines:
            m = BOX.match(line)
            if m:
                state = m.group(1) == " "
                continue
            if state is None:
                continue
            if not line.startswith(" "):
                state = None
                continue
            i = re.match(r"^\s+id:\s*(\S+)", line)
            if i:
                out[i.group(1)] = state
    return out


def process_lines(ps_file=None):
    if ps_file:
        return pathlib.Path(ps_file).read_text(encoding="utf-8").splitlines()
    cmd = ["ps", "-eo", "args"] if os.name != "nt" else ["wmic", "process", "get", "CommandLine"]
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout.splitlines()
    except Exception:
        return None


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.environ.get("CLAUDE_PROJECT_DIR") or ".")
    ap.add_argument("--ps-output")
    a = ap.parse_args(argv)
    repo = pathlib.Path(a.repo)
    items = load(repo / ".claude" / "rules" / "instruments.json").get("instruments") or []
    if not items:
        return 0
    causes = cause_states(repo)
    procs = process_lines(a.ps_output)
    for it in items:
        name, cause = it.get("id", "?"), it.get("cause", "")
        if cause not in causes:
            print(f"!! instrument '{name}': its cause '{cause}' stands in no registered ledger — tie it to the open "
                  "ledger entry, or remove the instrument")
            continue
        if not causes[cause]:
            continue  # cause explained: the instrument is no longer owed
        if procs is None:
            print(f"instrument '{name}': process list unreadable — not checked (cause '{cause}' is open)")
            continue
        if not any(it.get("match", "\0") in p for p in procs):
            print(f"!! instrument '{name}' is not running, its cause '{cause}' is still open — re-arm it detached: "
                  f"{it.get('start', '(no start command named)')}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
