#!/usr/bin/env python3
"""Orphan check: processes a session left running after it ended — reported, never ended.

WHY (2026-10-11, macOS instance): a recorder started from an earlier session's scratch
folder ran 16 h with no parent, held a controller's serial port and wrote 175 MB into the
operator's project folder; it was found by accident. The same day: twelve test children,
2-3 days old, left by older runs of a core fixture. Nothing at the session start looked
for either. A session that ends does not end what it started in the background.

What counts: a process whose parent is gone (PPID 1 — re-parented to launchd/init), older
than --min-age (default 1 h), whose command line names a session location: a Claude
session temp folder (`/claude-<uid>/`), the brain root, or a path pattern the instance
adds. A wanted long-runner of the same shape (a dashboard, a bridge) is declared in the
instance file with its reason and stays silent.

REPORT ONLY. Ending a process is the operator's or the AI's act after reading what it
does — a check that kills cannot tell a leak from a service.

Instance data: <repo>/.claude/rules/orphan-check.json
  {"paths": ["<regex>", ...], "allow": [{"match": "<regex>", "why": "<reason>"}, ...]}
  An allow entry without a reason is ignored (a declaration nobody can check).

Usage: orphan-check.py [--repo DIR] [--min-age SECONDS] [--ps-file FILE]
  --ps-file  read `ps -axo pid=,ppid=,etime=,command=` output from a file (fixtures)
Output: one `!!` line plus up to five process lines when something is found; one
`NOT checked` line when there is no `ps` (Windows); silent otherwise. Exit 0 always.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass

BUILTIN_PATHS = [r"/claude-\d+/"]
SHOW = 5


def etime_seconds(s):
    """ps etime: [[dd-]hh:]mm:ss -> seconds."""
    days, _, rest = s.rpartition("-")
    parts = [int(p) for p in rest.split(":")]
    while len(parts) < 3:
        parts.insert(0, 0)
    h, m, sec = parts
    return (int(days) if days else 0) * 86400 + h * 3600 + m * 60 + sec


def load_instance(repo):
    try:
        with open(os.path.join(repo, ".claude", "rules", "orphan-check.json"), encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        return [], []
    paths = [p for p in d.get("paths", []) if isinstance(p, str)]
    allow = [a["match"] for a in d.get("allow", [])
             if isinstance(a, dict) and a.get("match") and str(a.get("why", "")).strip()]
    return paths, allow


def compile_all(patterns):
    out = []
    for p in patterns:
        try:
            out.append(re.compile(p))
        except re.error:
            pass
    return out


def ps_lines(ps_file):
    if ps_file:
        with open(ps_file, encoding="utf-8") as f:
            return f.read().splitlines()
    if not shutil.which("ps"):
        return None
    try:
        r = subprocess.run(["ps", "-axo", "pid=,ppid=,etime=,command="],
                           capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    # A `ps` without these options (Git Bash on Windows) is no measurement — not "nothing".
    return r.stdout.splitlines() if r.returncode == 0 else None


def human(sec):
    if sec >= 86400:
        return f"{sec // 86400} d {sec % 86400 // 3600} h"
    return f"{sec // 3600} h {sec % 3600 // 60} min"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
    ap.add_argument("--min-age", type=int, default=3600)
    ap.add_argument("--ps-file")
    a = ap.parse_args()

    lines = ps_lines(a.ps_file)
    if lines is None:
        print("orphan check: NOT checked on this system (no POSIX `ps`) — processes left by "
              "earlier sessions are not looked for here.")
        return 0

    inst_paths, inst_allow = load_instance(a.repo)
    repo = os.path.abspath(a.repo).replace("\\", "/")
    where = compile_all(BUILTIN_PATHS + [re.escape(repo + "/")] + inst_paths)
    allow = compile_all(inst_allow)

    found = []
    for line in lines:
        f = line.split(None, 3)
        if len(f) < 4 or f[1] != "1":
            continue
        try:
            age = etime_seconds(f[2])
        except ValueError:
            continue
        cmd = f[3]
        if age < a.min_age or not any(r.search(cmd) for r in where):
            continue
        if any(r.search(cmd) for r in allow):
            continue
        found.append((age, f[0], cmd))

    if not found:
        return 0
    found.sort(reverse=True)
    print(f"!! orphaned processes: {len(found)} still running without the session that "
          "started them (no parent, older than "
          f"{a.min_age // 60} min, started from a session folder) — for the AI: read what "
          "each does; end a leak by its pid, declare a wanted one in "
          ".claude/rules/orphan-check.json with its reason")
    for age, pid, cmd in found[:SHOW]:
        print(f"   pid {pid} · {human(age)} · {cmd[:160]}")
    if len(found) > SHOW:
        print(f"   (+{len(found) - SHOW} more)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
