#!/usr/bin/env python3
"""fork-drift.py — fork work that never reached the core, and a core consumed from a fork.

WHY (operator direction 2026-10-11): the core exists so that every brain runs the same
state. Collaborators have write access and branch IN the repo; a fork branch gets no CI,
is seen by nobody and is forgotten. Measured the day this was written: two collaborator
forks, their main 167 and 314 commits behind, about twenty leftover branches of merged
PRs, one fix that had lived only on a fork branch for six weeks, one open PR still served
from a fork. Nothing had said so, because the forks only cost silence.

What it reports — one plain line per finding, prefixed `!!`, then one summary line:
  - a fork branch with commits that are not in core main and whose work has no OPEN or
    MERGED PR in the core (by head branch name) and whose commit subjects are not found in
    core main either (work carried over by another PR with authorship kept keeps its
    subject);
  - an OPEN PR in the core whose head lives in a fork (move the branch into the repo);
  - a fork whose main carries commits of its own;
  - `--brain <path>`: that brain's core/ submodule fetches from an owner other than the
    core repo's owner (the brain consumes a fork).
Silent apart from the summary when nothing is off.

WHAT IT CANNOT TELL, said instead of guessed: work merged by squash under a reworded title
and with reworded commit subjects matches neither the branch name nor the subjects — it is
reported as not landed (the safe direction: a person looks once and deletes the branch).
A CLOSED PR without a successor is reported the same way.

Network: one GitHub call for the fork list, two per fork plus one per fork branch, one PR
list. Meant for the brain-scan's machine checks, NOT the session start.

Usage: fork-drift.py [--repo <owner>/<name>] [--brain <path>]
  --repo   core repo slug; default: parsed from this checkout's origin remote
Exit 0 = ran (findings or not), 2 = could not read GitHub (said so, never "nothing").
Fixture hook: FORK_DRIFT_FIXTURE=<json file> maps "<gh args joined by spaces>" to the
answer and "git-log" to a list of core-main subjects (scripts/fork-drift-test.py).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_FIXTURE = None


def fixture():
    global _FIXTURE
    if _FIXTURE is None:
        p = os.environ.get("FORK_DRIFT_FIXTURE")
        _FIXTURE = json.loads(Path(p).read_text(encoding="utf-8")) if p else {}
    return _FIXTURE


def gh(*args):
    """JSON answer of `gh <args>`, or None when GitHub could not be read."""
    if os.environ.get("FORK_DRIFT_FIXTURE"):
        return fixture().get(" ".join(args))
    try:
        p = subprocess.run(["gh", *args], capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if p.returncode != 0:
        return None
    try:
        return json.loads(p.stdout or "null")
    except ValueError:
        return None


def api_list(path):
    """Every page of a list endpoint (100 per page)."""
    out, page = [], 1
    while True:
        sep = "&" if "?" in path else "?"
        chunk = gh("api", f"{path}{sep}per_page=100&page={page}")
        if chunk is None:
            return None
        out += chunk
        if len(chunk) < 100:
            return out
        page += 1


def owner_of(url: str) -> str:
    """Owner part of a GitHub remote URL (https or ssh form); '' when not GitHub-shaped."""
    m = re.search(r"github\.com[:/]+([^/]+)/[^/]+?(?:\.git)?/?$", url.strip())
    return m.group(1) if m else ""


def slug_of(url: str) -> str:
    m = re.search(r"github\.com[:/]+([^/]+/[^/]+?)(?:\.git)?/?$", url.strip())
    return m.group(1) if m else ""


def git_out(cwd, *args):
    try:
        p = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=30)
        return p.stdout.strip() if p.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def main_subjects():
    """Every subject core main knows: commit subjects AND the `* <subject>` lines a squash
    merge writes into its body for each commit it carried (measured 2026-10-11: two fork
    commits taken over by successor PRs with authorship kept appear only there)."""
    if os.environ.get("FORK_DRIFT_FIXTURE"):
        lines = fixture().get("git-log", [])
    else:
        lines = []
        for ref in ("origin/main", "main"):
            log = git_out(ROOT, "log", ref, "--format=%B")
            if log:
                lines = log.splitlines()
                break
    return {l.strip()[2:].strip() if l.strip().startswith("* ") else l.strip() for l in lines if l.strip()}


def landed(subject: str, subjects: set) -> bool:
    """A subject is in main as itself, or as a squash title `<subject> (#n)`."""
    return subject in subjects or any(s.startswith(subject + " (#") for s in subjects)


def consumed_from_fork(brain: Path, core_owner: str) -> list:
    """The brain's core/ submodule must fetch from the core repo's owner, never a fork.
    Called by the brain-scan here; device-status.py should call it too once it is merged."""
    url = git_out(brain / "core", "remote", "get-url", "origin")
    if not url:
        return []
    o = owner_of(url)
    if o and core_owner and o.lower() != core_owner.lower():
        return [f"!! this brain's core/ fetches from {slug_of(url) or url} — a fork, not the core repo "
                f"({core_owner}); consume the core only from the org repo at the released pin "
                f"(core/scripts/brain-update.sh resets the remote)"]
    return []


def fork_findings(repo: str):
    owner = repo.split("/", 1)[0]
    forks = api_list(f"repos/{repo}/forks")
    if forks is None:
        return None, 0
    prs = gh("pr", "list", "-R", repo, "--state", "all", "--limit", "1000",
             "--json", "number,state,headRefName,headRepositoryOwner")
    if prs is None:
        return None, len(forks)
    subjects = main_subjects()
    lines = []
    for pr in prs:
        hro = ((pr.get("headRepositoryOwner") or {}).get("login") or "")
        if pr.get("state") == "OPEN" and hro and hro.lower() != owner.lower():
            lines.append(f"!! open PR #{pr['number']} is served from the fork of {hro} — push its branch "
                         f"into {repo} and retarget, so it gets CI and stays visible")
    by_head = {}
    for pr in prs:
        by_head.setdefault(pr.get("headRefName", ""), []).append(pr.get("state"))
    for f in forks:
        fork = f["full_name"]
        default = f.get("default_branch") or "main"
        cmp_main = gh("api", f"repos/{fork}/compare/{owner}:{default}...{default}")
        if cmp_main and cmp_main.get("ahead_by", 0) > 0:
            lines.append(f"!! fork {fork}: its {default} carries {cmp_main['ahead_by']} commit(s) of its own "
                         f"(behind the core by {cmp_main.get('behind_by', '?')})")
        branches = api_list(f"repos/{fork}/branches")
        if branches is None:
            lines.append(f"!! fork {fork}: branches could not be read — not checked")
            continue
        for b in branches:
            name = b["name"]
            if name == default:
                continue
            states = by_head.get(name, [])
            if "OPEN" in states or "MERGED" in states:
                continue
            cmp = gh("api", f"repos/{fork}/compare/{owner}:{default}...{name}")
            if cmp is None:
                lines.append(f"!! fork {fork} branch {name}: could not be compared — not checked")
                continue
            ahead = cmp.get("commits") or []
            if not ahead:
                continue
            subj = [(c.get("commit") or {}).get("message", "").split("\n", 1)[0] for c in ahead]
            open_subj = [s for s in subj if s and not landed(s, subjects)]
            if not open_subj:
                continue
            last = ((ahead[-1].get("commit") or {}).get("committer") or {}).get("date", "")[:10]
            why = "closed PR without merge" if "CLOSED" in states else "no PR"
            lines.append(f"!! fork {fork} branch {name} ({why}, last commit {last or '?'}): "
                         f"{len(open_subj)} commit(s) not in the core — \"{open_subj[0][:90]}\""
                         f"{' …' if len(open_subj) > 1 else ''}; open a PR from a branch in {repo} "
                         f"or delete the fork branch")
    return lines, len(forks)


def main() -> int:
    # brain-scan-prep.py parses this output: same bytes on every platform (docs/os-traps.md OS-9).
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default="")
    ap.add_argument("--brain", default="")
    a = ap.parse_args()
    repo = a.repo or slug_of(git_out(ROOT, "remote", "get-url", "origin"))
    if not repo:
        print("fork drift summary: NOT checked — no core repo slug (pass --repo owner/name)")
        return 2
    lines, n = fork_findings(repo)
    if lines is None:
        print(f"fork drift summary: NOT checked — GitHub could not be read for {repo} "
              "(gh missing or not logged in); this is not 'no drift'")
        return 2
    if a.brain:
        lines += consumed_from_fork(Path(a.brain), repo.split("/", 1)[0])
    for l in lines:
        print(l)
    print(f"fork drift summary: {n} fork(s) of {repo}, {len(lines)} finding(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
