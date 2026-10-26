#!/usr/bin/env python3
"""shared-reach-check.py — did what this session changed with reach beyond this brain reach the shared memory?

WHY (operator, 2026-10-25, after a collaborator's AI drew the event network from fragments while the
generic network knowledge sat only in the private brain): "the whole essence of the decisions and the state
of the art should be available to the colleagues" and "that should be checked as part of the session close
— whether every essential piece of information also went into the shared memory (all domains, the occasion is
network engineering)". Measured on that brain: the close skill had carried the CROSS-INSTANCE GATE as prose
since 2026-08-17 ("ask, per finding, whether its reach goes past this machine"); nothing mechanical read the
documents, only the instance's ledger aggregator counted `reach: shared` entries without an export. The same
class as the beta-tag rule of the same day: a clear instruction held by prose alone.

THE INVARIANT: domain knowledge with reach beyond this brain (decisions, schemes, operating rules, state of the
art) lives ONCE, canonically in the shared memory; the private brain keeps lab state, access, measurement
protocols, ledgers, conversation protocols — and a POINTER in every private document whose essence moved:
    CANONICAL in shared memory: <topic>/<file>.md      (marker words per instance: `markers`)
At close, three measurements, none a guess:
  1. every private domain document CHANGED in the window (git log since --since under `domain_roots`) that
     carries a pointer: the shared file exists and its last commit is not older than the private change —
     else FAIL (the private side moved on, the canonical copy did not);
  2. every such document WITHOUT a pointer is named: "changed privately, no shared counterpart — lab or
     essence?" (a question the close report answers in one line each; the exclude list keeps ledgers,
     change logs, runlogs and readouts out of it);
  3. every open ledger entry with `reach: shared` (ledgers from `.claude/rules/ledgers.json`, the registry
     ledger-reconcile and open-items read) whose `id:` no shared file mentions — FAIL (the core's Project
     Work Ledgers rule #3: `reach: shared` is exported, deliberately, at session close).

WHERE IT RUNS: at session close (skill session-close, next to lesson-carriers.py and commitments.py). A REPORT
with FAIL lines, not a hook: the close reads the lines and answers each one (push the shared file, write the
export, or say "lab" / "stays private" for the unpointed ones). Exit 0 always.

Instance data: `.claude/rules/shared-reach.json`
    {"shared_repo": "~/Projects/brain-shared-memory",
     "domain_roots": ["docs"],
     "exclude": ["offene-punkte", "change-log", "session-log", "decision-log", "runlog", "readouts",
                 "exports", "configs", "protokoll", "memory-snapshot", "maintenance/", "research/"],
     "markers": ["CANONICAL in shared memory:"]}
Usage: shared-reach-check.py [--repo DIR] [--shared DIR] [--since YYYY-MM-DD] [--json]
Output: one line per finding, then
`shared-reach summary: changed=N pointed=N stale=N unpointed=N shared_entries=N unexported=N`.
"""
from __future__ import annotations
import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys

# OS-9: the session-close step parses this output — pin the bytes
try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass

DEFAULTS = {
    "shared_repo": os.path.join("~", "Projects", "brain-shared-memory"),
    "domain_roots": ["docs"],
    "exclude": ["offene-punkte", "change-log", "session-log", "decision-log", "runlog", "readouts",
                "exports", "configs", "protokoll", "memory-snapshot", "maintenance/", "research/"],
    "markers": ["CANONICAL in shared memory:"],
    "grace_hours": 24,
}


def load_config(repo: str) -> dict:
    cfg = dict(DEFAULTS)
    path = os.path.join(repo, ".claude", "rules", "shared-reach.json")
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        for k in DEFAULTS:
            if k in data:
                cfg[k] = data[k]
    except (OSError, ValueError):
        pass
    return cfg


def git(repo: str, *args: str) -> str:
    try:
        return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def changed_files(repo: str, since: str, roots: list[str], exclude: list[str]) -> list[str]:
    # Not `git log --since`: git stops walking at the FIRST commit older than the limit and never
    # looks below it, so one commit with an old date (a rebase, a clock skew, a backdated import)
    # hides every younger change beneath it (measured in this check's own fixture). The window is
    # applied per commit here instead.
    out = git(repo, "log", "--format=@@%cI", "--name-only", "--", *roots)
    seen: list[str] = []
    inside = False
    for line in out.splitlines():
        if line.startswith("@@"):
            inside = line[2:12] >= since
            continue
        if not inside:
            continue
        p = line.strip().replace("\\", "/")
        if not p.endswith(".md") or p in seen:
            continue
        if any(x in p for x in exclude):
            continue
        if os.path.isfile(os.path.join(repo, p)):
            seen.append(p)
    return seen


def last_commit_date(repo: str, path: str) -> str:
    return git(repo, "log", "-1", "--format=%cI", "--", path).strip()


def newer_by_hours(a: str, b: str) -> float:
    """Hours by which ISO date `a` is newer than `b`; 0 when either is unparsable."""
    try:
        da = dt.datetime.fromisoformat(a.replace("Z", "+00:00"))
        db = dt.datetime.fromisoformat(b.replace("Z", "+00:00"))
        return (da - db).total_seconds() / 3600.0
    except ValueError:
        return 0.0


def pointer_target(repo: str, path: str, markers: list[str]) -> str:
    if not markers:
        return ""  # no marker words = nothing can be a pointer (an empty alternation would match everything)
    rx = re.compile(r"(?:%s)\s*`?([\w./-]+\.md)`?" % "|".join(re.escape(m) for m in markers))
    try:
        with open(os.path.join(repo, path), encoding="utf-8", errors="replace") as f:
            head = f.read(4000)
    except OSError:
        return ""
    m = rx.search(head)
    return m.group(1) if m else ""


def ledgers(repo: str) -> list[str]:
    try:
        with open(os.path.join(repo, ".claude", "rules", "ledgers.json"), encoding="utf-8") as f:
            return [p for p in json.load(f).get("ledgers", []) if isinstance(p, str)]
    except (OSError, ValueError, AttributeError):
        return []


ENTRY_RX = re.compile(r"^\s*-\s*\[ \]\s")
ID_RX = re.compile(r"\bid:\s*`?([\w-]+)`?")
REACH_RX = re.compile(r"\breach:\s*shared\b")


def shared_entries(repo: str) -> list[tuple[str, str]]:
    """(ledger, id) of every OPEN `- [ ]` entry carrying `reach: shared` and an `id:`."""
    found: list[tuple[str, str]] = []
    for led in ledgers(repo):
        try:
            with open(os.path.join(repo, led), encoding="utf-8", errors="replace") as f:
                lines = f.read().splitlines()
        except OSError:
            continue
        block: list[str] = []
        def flush():
            text = "\n".join(block)
            if block and ENTRY_RX.match(block[0]) and REACH_RX.search(text):
                m = ID_RX.search(text)
                if m:
                    found.append((led, m.group(1)))
        for ln in lines:
            if re.match(r"^\s*-\s*\[[ xX]\]\s", ln) or ln.startswith("#"):
                flush()
                block = [ln]
            else:
                block.append(ln)
        flush()
    return found


def shared_mentions(shared: str, ident: str) -> bool:
    out = git(shared, "grep", "-l", "--fixed-strings", ident, "--", "*.md")
    return bool(out.strip())


def main() -> int:
    ap = argparse.ArgumentParser(description="what this session changed with reach — did it reach the shared memory?")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--shared", help="shared-memory repo (default from instance data, else ~/Projects/brain-shared-memory)")
    ap.add_argument("--since", help="window start YYYY-MM-DD (default: today)")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    cfg = load_config(a.repo)
    shared = os.path.expanduser(a.shared or cfg["shared_repo"])
    since = a.since or dt.date.today().isoformat()
    result = {"changed": 0, "pointed": 0, "stale": [], "unpointed": [], "shared_entries": 0, "unexported": [],
              "shared_repo_ok": os.path.isdir(os.path.join(shared, ".git"))}
    if not result["shared_repo_ok"]:
        print(f"shared-reach: no shared-memory repo at {shared} — NOT checked")
    for p in changed_files(a.repo, since, cfg["domain_roots"], cfg["exclude"]):
        result["changed"] += 1
        target = pointer_target(a.repo, p, cfg["markers"])
        if not target:
            result["unpointed"].append(p)
            continue
        result["pointed"] += 1
        if not result["shared_repo_ok"]:
            continue
        tpath = os.path.join(shared, target)
        if not os.path.isfile(tpath):
            result["stale"].append({"private": p, "shared": target, "why": "shared file missing"})
            continue
        private_date = last_commit_date(a.repo, p)
        shared_date = last_commit_date(shared, target)
        # Grace window: the move itself writes the shared file first and the private pointer minutes
        # later, so "private newer than shared" is only a finding past `grace_hours` (default 24).
        if private_date and shared_date and newer_by_hours(private_date, shared_date) > cfg["grace_hours"]:
            result["stale"].append({"private": p, "shared": target,
                                    "why": f"shared {shared_date[:10]} older than private {private_date[:10]}"})
    for led, ident in shared_entries(a.repo):
        result["shared_entries"] += 1
        if result["shared_repo_ok"] and not shared_mentions(shared, ident):
            result["unexported"].append({"ledger": led, "id": ident})
    if a.json:
        print(json.dumps(result, ensure_ascii=False, indent=1))
        return 0
    for s in result["stale"]:
        print(f"FAIL shared-reach: {s['private']} points to {s['shared']} — {s['why']}; update or push the canonical file")
    for u in result["unexported"]:
        print(f"FAIL shared-reach: ledger {u['ledger']} entry `{u['id']}` is reach: shared but no shared file names it — export it")
    for p in result["unpointed"]:
        print(f"shared-reach: {p} changed privately, no shared counterpart — lab or essence? (one line in the close report)")
    print("shared-reach summary: changed=%d pointed=%d stale=%d unpointed=%d shared_entries=%d unexported=%d%s" % (
        result["changed"], result["pointed"], len(result["stale"]), len(result["unpointed"]),
        result["shared_entries"], len(result["unexported"]),
        "" if result["shared_repo_ok"] else " (shared repo missing — NOT checked)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
