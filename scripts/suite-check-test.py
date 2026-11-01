#!/usr/bin/env python3
"""Fixture for suite-check.py's marketplace check — both directions, offline, temp repos only.

Positive: entries on existing release tags of the repo itself pass; a foreign repo's tag is
not checkable offline and passes; a checkout without tags (a shallow CI clone) only warns.
Planted: no ref, a branch ref, a tag the repo does not have, a relative source and an
unparseable file must each be an ERROR. Last: the core's own marketplace.json carries no
ERROR (a WARN is allowed where the checkout has no tags).
"""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import git_sandbox  # noqa: E402,F401 - the host git config never reaches a fixture repo

spec = importlib.util.spec_from_file_location("suite_check", HERE / "suite-check.py")
sc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sc)

fails = 0


def ok(cond: bool, what: str):
    global fails
    print(("PASS " if cond else "FAIL ") + what)
    if not cond:
        fails += 1


def git(repo: Path, *args: str):
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)


def make_repo(root: Path, name: str, tags=("v1.0.0", "v1.0.1")) -> Path:
    repo = root / name
    (repo / ".claude-plugin").mkdir(parents=True)
    git(repo, "init", "-q")
    git(repo, "remote", "add", "origin", "https://github.com/o/r.git")
    git(repo, "commit", "-q", "--allow-empty", "-m", "init")
    for t in tags:
        git(repo, "tag", t)
    return repo


def entry(name: str, ref=None, repo="o/r") -> dict:
    src = {"source": "github", "repo": repo}
    if ref is not None:
        src["ref"] = ref
    return {"name": name, "source": src, "description": "x"}


def levels(repo: Path, plugins) -> list:
    path = repo / ".claude-plugin" / "marketplace.json"
    if isinstance(plugins, str):
        path.write_text(plugins, encoding="utf-8")
    else:
        path.write_text(json.dumps({"name": "m", "owner": {"name": "o"}, "plugins": plugins}),
                        encoding="utf-8")
    return [lvl for lvl, _ in sc.marketplace_findings(repo)]


with tempfile.TemporaryDirectory() as td:
    base = Path(td)
    repo = make_repo(base, "tagged")
    ok(levels(repo, [entry("a", "v1.0.0"), entry("a-next", "v1.0.1")]) == [],
       "stable + beta on existing tags of this repo: no finding")
    ok(levels(repo, [entry("b", "v7.7.7", repo="other/suite")]) == [],
       "a foreign repo's tag is not checked offline: no finding")
    ok(levels(repo, [entry("a")]) == ["ERROR"], "no ref (default branch): ERROR")
    ok(levels(repo, [entry("a", "main")]) == ["ERROR"], "ref on main: ERROR")
    ok(levels(repo, [entry("a", "v9.9.9")]) == ["ERROR"], "ref on a missing tag: ERROR")
    ok(levels(repo, [{"name": "a", "source": "./"}]) == ["ERROR"], "relative source: ERROR")
    ok(levels(repo, "{not json") == ["ERROR"], "unparseable marketplace.json: ERROR")
    levels(repo, [entry("a", "main")])
    contract = json.loads(sc.CONTRACT_PATH.read_text(encoding="utf-8"))
    ok(any(lvl == "ERROR" and "marketplace.json" in msg for lvl, msg in sc.check(repo, contract)),
       "check() carries the marketplace finding (wired, not only defined)")
    untagged = make_repo(base, "shallow", tags=())
    ok(levels(untagged, [entry("a", "v1.0.0")]) == ["WARN"],
       "a checkout without tags (shallow clone): WARN, not ERROR")

core_levels = [lvl for lvl, _ in sc.marketplace_findings(HERE.parent)]
ok((HERE.parent / ".claude-plugin" / "marketplace.json").exists() and "ERROR" not in core_levels,
   "the core's own marketplace.json: no ERROR")

print(f"\n{'FAIL' if fails else 'OK'}: suite-check marketplace fixture ({fails} failing)")
sys.exit(1 if fails else 0)
