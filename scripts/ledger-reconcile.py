#!/usr/bin/env python3
"""Ledger reconcile: does the ledger's checkbox still say what the system says?

WHY (2026-10-19, a proving brain): 11 of the 12 orders a brain-scan had filed four days
earlier were done and still listed open. One commit carried out the fixes AND entered the
same findings as `- [ ]` — the state was copied from the report, never measured. The
session start and the ledger aggregator trust the checkbox, so the done work kept showing
as open work and was handed around as such. The operator's words: when something done is
listed as not done, find out why and fix the cause, as a standard, not case by case.

The carrier: an entry names how "done" is measured. A ledger entry (a `- [ ]` / `- [x]`
line plus its indented field lines) may carry
    check: <shell command>          exit 0 = the thing is done (read-only, fast)
    check: none — <why not>         not machine-checkable, said so on purpose
The script runs every `check:` of the registered ledgers and reports:
  DONE-OPEN   the entry is open, its check passes      -> tick it, and name why it was missed
  REGRESSED   the entry is ticked, its check fails     -> reopen it, or the check is wrong
  NO-CHECK    an open entry dated on/after `ratchet_since` names no check at all
A check that times out or cannot start is reported as such, never as done.

Ledgers are instance data: `.claude/rules/ledgers.json`
    {"ledgers": ["docs/maintenance/orders.md", ...], "ratchet_since": "YYYY-MM-DD",
     "timeout_s": 20}
Paths are relative to the brain root. No file = nothing registered (said once, not a gate).

Usage: ledger-reconcile.py [--root DIR] [--brief] [--ledger PATH ...] [--since DATE]
  --brief   session-start form: silent when clean, one `!!` line per class otherwise
Exit: 0 always without --strict; with --strict 1 when DONE-OPEN or REGRESSED exist.
Checks run with the brain root as working directory; they must only read.
"""
import argparse
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except Exception:
    pass

ENTRY = re.compile(r"^- \[( |x|X)\] (.*)$")
FIELD = re.compile(r"^\s{2,}([a-z_-]+):\s?(.*)$")
DATE = re.compile(r"\b(20\d\d-\d\d-\d\d)\b")
NONE = re.compile(r"^none\b", re.I)


def entries(text):
    """Yield dicts: done, title, fields, first_date, line — one per checkbox entry."""
    cur = None
    for n, line in enumerate(text.splitlines(), 1):
        m = ENTRY.match(line)
        if m:
            if cur:
                yield cur
            cur = {"done": m.group(1) != " ", "title": m.group(2).strip(), "fields": {},
                   "text": line, "line": n}
            continue
        if cur is None:
            continue
        if not line.strip() or not line.startswith(" "):
            yield cur
            cur = None
            continue
        cur["text"] += "\n" + line
        f = FIELD.match(line)
        if f and f.group(1) not in cur["fields"]:
            cur["fields"][f.group(1)] = f.group(2).strip()
    if cur:
        yield cur


def find_shell(explicit=None):
    """The POSIX shell that runs the checks, as a native path — never WSL's launcher.

    On Windows a bare-name lookup from Python finds System32's WSL launcher before Git Bash
    (docs/os-traps.md OS-14), so Git Bash is derived from git's own install folder:
    <Git>/cmd/git.exe or <Git>/mingw64/bin/git.exe -> <Git>/bin/bash.exe.
    """
    if explicit:
        return explicit
    env = os.environ.get("LEDGER_RECONCILE_SHELL")
    if env:
        return env
    if os.name == "nt":
        git = shutil.which("git")
        if not git:
            return None
        here = pathlib.Path(git).resolve().parent
        for base in (here.parent, here.parent.parent):
            cand = base / "bin" / "bash.exe"
            if cand.is_file():
                return str(cand)
        return None
    return shutil.which("bash")


def run_check(cmd, root, timeout, shell):
    """'pass' | 'fail' | 'timeout' | 'error'."""
    if not shell:
        return "error"
    try:
        r = subprocess.run([shell, "-c", cmd], cwd=root, timeout=timeout,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return "timeout"
    except OSError:
        return "error"
    return "pass" if r.returncode == 0 else "fail"


def label(e, path):
    # Some ledgers keep several fields on one line ("id: x · class: todo"): the id is its first word.
    ident = (e["fields"].get("id") or "").split()
    return ident[0] if ident else f"{path}:{e['line']}"


def reconcile(root, ledgers, since, timeout, shell):
    out = {"done_open": [], "regressed": [], "no_check": [], "broken": [], "missing": []}
    for rel in ledgers:
        path = pathlib.Path(root) / rel
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            out["missing"].append(rel)
            continue
        for e in entries(text):
            chk = e["fields"].get("check", "")
            if not chk:
                d = DATE.search(e["text"])
                if not e["done"] and since and d and d.group(1) >= since:
                    out["no_check"].append(label(e, rel))
                continue
            if NONE.match(chk):
                continue
            res = run_check(chk, root, timeout, shell)
            if res in ("timeout", "error"):
                out["broken"].append(f"{label(e, rel)} ({res})")
            elif res == "pass" and not e["done"]:
                out["done_open"].append(label(e, rel))
            elif res == "fail" and e["done"]:
                out["regressed"].append(label(e, rel))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    ap.add_argument("--ledger", action="append", default=[])
    ap.add_argument("--since")
    ap.add_argument("--brief", action="store_true")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--shell", help="POSIX shell that runs the checks (native path)")
    a = ap.parse_args()

    cfg = {}
    cfg_path = pathlib.Path(a.root) / ".claude" / "rules" / "ledgers.json"
    if not a.ledger:
        try:
            cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            if not a.brief:
                print("ledger-reconcile: no ledgers registered (.claude/rules/ledgers.json) - nothing checked")
            return 0
    ledgers = a.ledger or cfg.get("ledgers") or []
    since = a.since or cfg.get("ratchet_since")
    timeout = int(cfg.get("timeout_s") or 20)
    shell = find_shell(a.shell)
    r = reconcile(a.root, ledgers, since, timeout, shell)

    def say(key, head, tail):
        items = r[key]
        if items:
            shown = ", ".join(items[:8]) + (f" (+{len(items) - 8} more)" if len(items) > 8 else "")
            print(f"!! ledger: {len(items)} {head}: {shown} - {tail}")

    say("done_open", "entr(y/ies) done but still open (its check passes)",
        "tick it with the evidence, and name why the ledger missed it (copied from a report? fixed in passing?)")
    say("regressed", "ticked entr(y/ies) whose check fails",
        "reopen it, or the check no longer measures the thing")
    say("broken", "check(s) that could not give an answer",
        "a check must be a fast, read-only command - fix it or write `check: none - <why>`"
        + ("" if shell else " (no POSIX shell found to run checks with)"))
    say("missing", "registered ledger file(s) not found", "fix .claude/rules/ledgers.json")
    say("no_check", f"open entr(y/ies) since {since} without a `check:` line",
        "name the command that measures done, or `check: none — <why not machine-checkable>`")
    if not a.brief and not any(r.values()):
        print(f"ledger-reconcile: {len(ledgers)} ledger(s) - every check agrees with its checkbox")
    if a.strict and (r["done_open"] or r["regressed"]):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
