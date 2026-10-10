#!/usr/bin/env python3
"""Fixture for repo-check.py — both directions, offline, local temp repos only.

Positive: a project repo built from templates/repo/ (plus hooksPath set) reports
nothing missing. Planted: the same repo with each carrier removed in turn must name
exactly that carrier. Negative control: a check that always passes (the stub below)
misses every planted case — proof the fixture can see a failure at all.
The protection answer is tested on the classifier with the measured GitHub texts.
"""
from __future__ import annotations

import importlib.util
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
CORE = HERE.parent
spec = importlib.util.spec_from_file_location("repo_check", HERE / "repo-check.py")
rc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rc)

fails = 0


def ok(cond: bool, what: str):
    global fails
    print(("PASS " if cond else "FAIL ") + what)
    if not cond:
        fails += 1


def git(repo: Path, *args: str):
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)


def make_project(root: Path) -> Path:
    repo = root / "proj"
    shutil.copytree(CORE / "templates" / "repo", repo)
    git(repo, "init", "-q")
    git(repo, "config", "core.hooksPath", ".githooks")
    return repo


def missing(repo: Path, kind: str = "") -> set[str]:
    return {i for s, i, _ in rc.check(repo, kind or rc.detect_kind(repo), "", offline=True) if s == "MISSING"}


with tempfile.TemporaryDirectory() as td:
    base = Path(td)
    repo = make_project(base)
    ok(rc.detect_kind(repo) == "project", "template repo is detected as a project")
    ok(missing(repo) == set(), "template repo + hooksPath: nothing missing")

    planted = {
        "workflow": lambda r: shutil.rmtree(r / ".github" / "workflows"),
        "pre_push": lambda r: (r / ".githooks" / "pre-push").unlink(),
        "pr_template": lambda r: (r / ".github" / "pull_request_template.md").unlink(),
        "gitattributes": lambda r: (r / ".gitattributes").write_text("* text=auto\n"),
        "hooks_path": lambda r: git(r, "config", "--unset", "core.hooksPath"),
    }
    for item, plant in planted.items():
        r = make_project(base / item)
        plant(r)
        got = missing(r)
        ok(item in got, f"planted: {item} removed is named")
        if item == "workflow":
            ok({"leak_scan", "pr_flow"} <= got, "planted: no workflow also means no leak scan, no PR trigger")
        # Negative control: with the kind's demands emptied the checker reports nothing,
        # so the planted assertion above would fail — it measures the checker, not luck.
        saved = rc.NEEDS["project"]
        rc.NEEDS["project"] = set()
        ok(item not in missing(r), f"negative control: emptied demands miss {item}")
        rc.NEEDS["project"] = saved

    # Kinds that take direct pushes by design are not asked for the PR fence.
    bm = base / "brain"
    (bm / "core").mkdir(parents=True)
    (bm / ".claude").mkdir()
    (bm / ".gitattributes").write_text("* text=auto eol=lf\n")
    git(bm, "init", "-q")
    ok(rc.detect_kind(bm) == "brain", "brain detected (core/ + .claude/)")
    ok(missing(bm) == set(), "brain: no pre-push or PR template demanded")

    sm = base / "shm"
    sm.mkdir()
    (sm / "INDEX.md").write_text("x\n")
    (sm / "ops").mkdir()
    (sm / "ops" / "LOG.md").write_text("x\n")
    git(sm, "init", "-q")
    ok(rc.detect_kind(sm) == "shared-memory", "shared memory detected (INDEX.md + an area LOG.md)")
    ok(missing(sm) == {"gitattributes"}, "shared memory without .gitattributes: only that is named")

    # Offline never claims protection.
    res = rc.check(repo, "project", "", offline=True)
    ok(("INFO", "protection") in {(s, i) for s, i, _ in res}, "offline: protection is INFO, not OK")

# Protection answers, texts as GitHub returns them (measured 2026-10-10).
ok(rc.classify_protection(0, "{}", "") == "enforced", "protection: 200 = enforced")
ok(rc.classify_protection(1, "", "gh: Upgrade to GitHub Pro or make this repository public "
                          "to enable this feature. (HTTP 403)") == "not-enforceable",
   "protection: 403 upgrade text = not enforceable on this plan")
ok(rc.classify_protection(1, "", "gh: Branch not protected (HTTP 404)") == "missing",
   "protection: 404 not protected = missing")
ok(rc.classify_protection(1, "", "gh: Bad credentials (HTTP 401)") == "unknown",
   "protection: other errors = unknown, never a pass")

print(f"repo-check-test: {'all pass' if not fails else str(fails) + ' FAIL'}")
sys.exit(1 if fails else 0)
