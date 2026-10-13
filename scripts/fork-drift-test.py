#!/usr/bin/env python3
"""Fixture for fork-drift.py, both directions, with GitHub served from a JSON fixture.

Positive: a fork branch with a commit that has no PR and is not in core main -> line;
an open PR served from a fork -> line; a fork main with own commits -> line; a brain whose
core/ fetches from another owner -> line; GitHub unreadable -> exit 2, "NOT checked".
Negative controls: a branch of a MERGED PR, a branch whose commit was carried into main by
a squash (subject only in the squash body) and a branch with nothing ahead -> silent; a
brain whose core/ fetches from the org -> silent.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOL = HERE / "fork-drift.py"
REPO = "org-a/core"
fails = 0


def check(name, cond, detail=""):
    global fails
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  -- {detail}"))
    if not cond:
        fails += 1


def commit(subject, date="2026-09-01T10:00:00Z"):
    return {"commit": {"message": subject + "\n\nbody", "committer": {"date": date}}}


def answers(forks, prs, branches, compares, log):
    d = {f"api repos/{REPO}/forks?per_page=100&page=1": forks,
         f"pr list -R {REPO} --state all --limit 1000 --json number,state,headRefName,headRepositoryOwner": prs,
         "git-log": log}
    for fork, names in branches.items():
        d[f"api repos/{fork}/branches?per_page=100&page=1"] = [{"name": n} for n in names]
    d.update(compares)
    return d


def run(data, tmp, *extra):
    fx = tmp / "fixture.json"
    fx.write_text(json.dumps(data), encoding="utf-8")
    env = dict(os.environ, FORK_DRIFT_FIXTURE=str(fx))
    p = subprocess.run([sys.executable, str(TOOL), "--repo", REPO, *extra], capture_output=True,
                       text=True, encoding="utf-8", env=env)
    return p.returncode, p.stdout


def git(*args):
    subprocess.run(["git", *args], check=True, capture_output=True)


tmp = Path(tempfile.mkdtemp())
try:
    fork = {"full_name": "pal/core", "default_branch": "main"}
    base = {"api repos/pal/core/compare/org-a:main...main": {"ahead_by": 0, "behind_by": 40, "commits": []}}

    # 1. unlanded fork branch -> one line
    data = answers([fork], [], {"pal/core": ["main", "fix/lost"]},
                   dict(base, **{"api repos/pal/core/compare/org-a:main...fix/lost":
                                 {"ahead_by": 1, "commits": [commit("fix(tool): a fix nobody got")]}}),
                   ["feat: something else (#12)"])
    rc, out = run(data, tmp)
    check("unlanded fork branch is named", rc == 0 and "fix/lost" in out and "no PR" in out, out)

    # 2. negative control: merged-PR branch, squash-carried branch, empty branch -> silent
    data = answers([fork],
                   [{"number": 5, "state": "MERGED", "headRefName": "fix/merged",
                     "headRepositoryOwner": {"login": "pal"}}],
                   {"pal/core": ["main", "fix/merged", "fix/carried", "fix/empty"]},
                   dict(base, **{
                       "api repos/pal/core/compare/org-a:main...fix/carried":
                           {"ahead_by": 1, "commits": [commit("fix(tool): carried with authorship")]},
                       "api repos/pal/core/compare/org-a:main...fix/empty": {"ahead_by": 0, "commits": []}}),
                   ["fix(tool): successor PR (#20)", "", "* fix(tool): carried with authorship"])
    rc, out = run(data, tmp)
    check("merged, squash-carried and empty branches stay silent",
          rc == 0 and "!!" not in out and "0 finding(s)" in out, out)

    # 3. open PR served from a fork, and a fork main with own commits
    data = answers([fork],
                   [{"number": 7, "state": "OPEN", "headRefName": "fix/open",
                     "headRepositoryOwner": {"login": "pal"}},
                    {"number": 8, "state": "OPEN", "headRefName": "fix/in-repo",
                     "headRepositoryOwner": {"login": "org-a"}}],
                   {"pal/core": ["main", "fix/open"]},
                   {"api repos/pal/core/compare/org-a:main...main": {"ahead_by": 2, "behind_by": 3, "commits": []}},
                   [])
    rc, out = run(data, tmp)
    check("open PR from a fork is named", "open PR #7" in out, out)
    check("open PR from the repo itself is not named", "#8" not in out, out)
    check("fork main with own commits is named", "carries 2 commit(s)" in out, out)

    # 4. GitHub unreadable -> exit 2, never "no drift"
    rc, out = run({}, tmp)
    check("unreadable GitHub: exit 2 and NOT checked", rc == 2 and "NOT checked" in out, out)

    # 5. core consumed from a fork vs. from the org
    empty = answers([], [], {}, {}, [])
    for owner, expect in (("pal", True), ("org-a", False)):
        brain = tmp / f"brain-{owner}"
        (brain / "core").mkdir(parents=True)
        git("-C", str(brain / "core"), "init", "-q")
        git("-C", str(brain / "core"), "remote", "add", "origin", f"https://github.com/{owner}/core.git")
        rc, out = run(empty, tmp, "--brain", str(brain))
        named = "fetches from" in out
        check(f"core/ fetching from {'a fork' if expect else 'the org'} is {'named' if expect else 'silent'}",
              named == expect, out)
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("fork-drift: all checks passed" if not fails else f"fork-drift: {fails} check(s) FAILED")
sys.exit(1 if fails else 0)
