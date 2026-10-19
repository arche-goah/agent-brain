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

Two bounds, because the checks run on their own at every session start:
- Only READ commands run. A check is parts joined by `&&`, `||` or `|`; every part must start
  with an allowed prefix (`allowed`, default ALLOWED below), any other shell control character
  (`;`, a single `&`, `<`, `>`, `(`, `)`, `$`, backtick, braces, newline) refuses the check, and
  so do options that write or start a program (`--output`, `--ext-diff`, `-O`, ...). A refused
  check is named, never run. "read-only" is then a property the script enforces.
- The session start never waits for the checks: it runs `--cached`, which prints the brief
  result of the PREVIOUS run (silent when that was clean) and starts the next run in the
  background — the brain-check pattern. Measured 2026-10-19 on a Windows brain: the start
  already took 18-28 s of its 30 s hook limit without this script, one start was cut at 31 s.
  The answer arrives one start later, said with its time.
- One time budget for the whole run (`budget_s`, default 30 s; each check also has
  `timeout_s`, default 5 s; a check starts only while its full timeout still fits). Checks the
  budget does not reach are counted as not run this time, never as done.

Ledgers are instance data: `.claude/rules/ledgers.json`
    {"ledgers": ["docs/maintenance/orders.md", ...], "ratchet_since": "YYYY-MM-DD",
     "timeout_s": 5, "budget_s": 10, "allowed": ["test", "grep", "git log", ...]}
Paths are relative to the brain root. No file = nothing registered (said once, not a gate).

Usage: ledger-reconcile.py [--root DIR] [--brief|--cached] [--ledger PATH ...] [--since DATE]
  --brief   silent when clean, one `!!` line per class otherwise
  --cached  what the session start runs: last run's --brief result now, next run in the background
            (result file .claude-state/ledger-reconcile.brief, its time in ...stamp)
Exit: 0 always without --strict; with --strict 1 when DONE-OPEN or REGRESSED exist.
Checks run with the brain root as working directory.
"""
import argparse
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time

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


# Prefixes a part of a check may start with — commands that read. A git subcommand is named in
# full, so `git push` or `git commit` never matches. An instance widens or narrows it with
# "allowed" in its ledgers.json; the list replaces this one, it does not add to it.
# `find` is NOT here: -delete/-exec make it a writer, and a check rarely needs it (`ls`, `test`).
ALLOWED = ["test", "[", "grep", "ls", "wc", "head", "tail", "cat", "diff",
           "git log", "git show", "git grep", "git rev-parse", "git ls-files", "git cat-file",
           "git merge-base", "git diff", "git status"]
# The shell grammar a check may use is closed, not filtered: parts joined by `&&`, `||` or `|`
# (a pipe), each part a plain command with words. After those separators are taken out, ANY
# other shell control character refuses the check — `;`, a single `&`, `<`, `>`, `(`, `)`,
# `$`, a backtick, a newline. A blocklist of known tricks loses to the next trick (review of
# this PR, 2026-10-19: `&`, `<(…)` and a `;` inside find's -exec passed the first list).
SPLIT = re.compile(r"\s*(?:&&|\|\||\|)\s*")
CONTROL = re.compile(r"[;&<>()$`\n\r{}]")
# Options of allowed commands that write a file or start another program.
WRITING_OPTION = re.compile(r"^(--output|--ext-diff|--textconv|-O|--open-files-in-pager|--exec)")


def permitted(cmd, allowed):
    """True when every part of the check is an allowed reading command and nothing can write."""
    parts = SPLIT.split(cmd.strip())
    if any(CONTROL.search(p) for p in parts):
        return False
    for part in parts:
        words = part.strip().lstrip("!").split()
        if not words:
            return False
        if not any(words[:len(p.split())] == p.split() for p in allowed):
            return False
        if any(WRITING_OPTION.match(w) for w in words[1:]):
            return False
    return True


def run_check(cmd, root, timeout, shell):
    """'pass' | 'fail' | 'timeout' | 'error'."""
    if not shell:
        return "error"
    # Windows: the --cached run is detached and has no console, so every check it starts would
    # get a NEW console — measured 2026-10-19 on a Windows brain: 4 checks 12.3 s with default
    # flags, 0.11 s with CREATE_NO_WINDOW (and presumably no window flashing per check).
    kw = {"creationflags": 0x08000000} if os.name == "nt" else {}
    try:
        r = subprocess.run([shell, "-c", cmd], cwd=root, timeout=timeout,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **kw)
    except subprocess.TimeoutExpired:
        return "timeout"
    except OSError:
        return "error"
    return "pass" if r.returncode == 0 else "fail"


def label(e, path):
    # Some ledgers keep several fields on one line ("id: x · class: todo"): the id is its first word.
    ident = (e["fields"].get("id") or "").split()
    return ident[0] if ident else f"{path}:{e['line']}"


def reconcile(root, ledgers, since, timeout, shell, allowed=ALLOWED, budget=10.0):
    out = {"done_open": [], "regressed": [], "no_check": [], "broken": [], "missing": [],
           "refused": [], "not_run": []}
    deadline = time.monotonic() + budget
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
            if not permitted(chk, allowed):
                out["refused"].append(label(e, rel))
                continue
            # A check starts only while its full timeout still fits the budget, so a check that
            # runs always gets its whole timeout — a slow one is "timeout", never cut short.
            if deadline - time.monotonic() < timeout:
                out["not_run"].append(label(e, rel))
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
    ap.add_argument("--cached", action="store_true")
    ap.add_argument("--out", help=argparse.SUPPRESS)   # the background run's result file
    a = ap.parse_args()

    if a.cached:
        return cached(a)

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
    timeout = float(cfg.get("timeout_s") or 5)
    budget = float(cfg.get("budget_s") or 30)
    allowed = cfg.get("allowed") or ALLOWED
    shell = find_shell(a.shell)
    r = reconcile(a.root, ledgers, since, timeout, shell, allowed, budget)
    lines = []

    def say(key, head, tail):
        items = r[key]
        if items:
            shown = ", ".join(items[:8]) + (f" (+{len(items) - 8} more)" if len(items) > 8 else "")
            lines.append(f"!! ledger: {len(items)} {head}: {shown} - {tail}")

    say("done_open", "entr(y/ies) done but still open (its check passes)",
        "tick it with the evidence, and name why the ledger missed it (copied from a report? fixed in passing?)")
    say("regressed", "ticked entr(y/ies) whose check fails",
        "reopen it, or the check no longer measures the thing")
    say("broken", "check(s) that could not give an answer",
        "a check must be a fast, read-only command - fix it or write `check: none - <why>`"
        + ("" if shell else " (no POSIX shell found to run checks with)"))
    say("refused", "check(s) refused, not run (not on the read-only allow list, or writing)",
        "rewrite it with a reading command, or widen `allowed` in .claude/rules/ledgers.json on purpose")
    say("not_run", f"check(s) not reached within the {budget:g} s budget",
        "not run this time (never counted as done) - make the checks faster, or raise `budget_s`")
    say("missing", "registered ledger file(s) not found", "fix .claude/rules/ledgers.json")
    say("no_check", f"open entr(y/ies) since {since} without a `check:` line",
        "name the command that measures done, or `check: none — <why not machine-checkable>`")
    if not a.brief and not any(r.values()):
        lines.append(f"ledger-reconcile: {len(ledgers)} ledger(s) - every check agrees with its checkbox")
    text = "".join(l + "\n" for l in lines)
    if a.out:
        out = pathlib.Path(a.out)
        tmp = out.with_name(f"{out.name}.{os.getpid()}")   # two starts at once never share a file
        # open(newline=) and not Path.write_text(newline=): the latter is 3.10+ (os-traps OS-13)
        with open(tmp, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        os.replace(tmp, out)
        with open(out.with_name(out.stem + ".stamp"), "w", encoding="utf-8", newline="\n") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M") + "\n")
    else:
        sys.stdout.write(text)
    if a.strict and (r["done_open"] or r["regressed"]):
        return 1
    return 0


def cached(a):
    """Session start: the previous run's brief result, the next run started in the background."""
    state = pathlib.Path(a.root) / ".claude-state"
    out = state / "ledger-reconcile.brief"
    try:
        prev = out.read_text(encoding="utf-8")
    except OSError:
        prev = ""
    if prev.strip():
        try:
            when = (state / "ledger-reconcile.stamp").read_text(encoding="utf-8").strip()
        except OSError:
            when = "an earlier start"
        sys.stdout.write(prev)
        print(f"   (ledger reconcile: result of {when}; the next run is measuring in the background)")
    try:
        state.mkdir(exist_ok=True)
    except OSError:
        return 0
    cmd = [sys.executable, str(pathlib.Path(__file__).resolve()), "--root", a.root,
           "--brief", "--out", str(out)]
    if a.shell:
        cmd += ["--shell", a.shell]
    for led in a.ledger:
        cmd += ["--ledger", led]
    if a.since:
        cmd += ["--since", a.since]
    kw = {"stdin": subprocess.DEVNULL, "stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL,
          "cwd": a.root}
    if os.name == "nt":
        kw["creationflags"] = 0x00000008 | 0x00000200   # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
    else:
        kw["start_new_session"] = True
    try:
        subprocess.Popen(cmd, **kw)
    except OSError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
