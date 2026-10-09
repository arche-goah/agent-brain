#!/usr/bin/env python3
"""Fixture tests for scripts/staged-names.py in a throwaway git repo.

Must block: a staged added line with a watched name (from `names` and from `instances`),
in any case. Must stay silent (the negative controls): the name only in a REMOVED line,
only in an UNSTAGED change, or only as part of a longer word. A missing watch list passes
but says so on stderr — an unconfigured guard must not look like a clean one.
The watched words are invented; no real name appears here.
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = str(Path(__file__).resolve().parent / "staged-names.py")


def git(repo, *args):
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)


def setup(d, names=("Zorblax Quint",), instances=("vexmoor",)):
    brain, repo = Path(d) / "brain", Path(d) / "repo"
    (brain / ".claude/rules").mkdir(parents=True)
    (brain / ".claude/rules/leak-names.json").write_text(
        json.dumps({"names": list(names), "instances": list(instances)}), encoding="utf-8", newline="\n")
    repo.mkdir()
    git(repo, "init", "-q")
    git(repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-q",
        "--allow-empty", "-m", "root")
    return brain, repo


def put(repo, name, text, stage=True):
    (repo / name).write_text(text, encoding="utf-8", newline="\n")
    if stage:
        git(repo, "add", name)


def run(repo, brain=None):
    env = {k: v for k, v in os.environ.items() if k != "BRAIN_DIR"}
    args = [sys.executable, SCRIPT] + ([str(brain)] if brain is not None else [])
    p = subprocess.run(args, cwd=repo, capture_output=True, text=True, encoding="utf-8", env=env)
    return p.returncode, p.stdout, p.stderr


def case(title, fn):
    with tempfile.TemporaryDirectory() as d:
        ok, why = fn(d)
    print(("ok  " if ok else "FAIL") + "  " + title + ("" if ok else f" - {why}"))
    return ok


def t_name_blocks(d):
    brain, repo = setup(d)
    put(repo, "a.md", "written by zorblax quint\n")
    rc, out, _ = run(repo, brain)
    return rc == 1 and "a.md: written by zorblax quint" in out, (rc, out)


def t_instance_blocks(d):
    brain, repo = setup(d)
    put(repo, "b.py", "SHOW = 'Vexmoor'\n")
    rc, out, _ = run(repo, brain)
    return rc == 1 and "b.py" in out, (rc, out)


def t_removed_line_passes(d):
    brain, repo = setup(d)
    put(repo, "c.md", "line one\nby zorblax quint\n")
    git(repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-q", "-m", "c")
    put(repo, "c.md", "line one\n")  # removing the name is exactly what should pass
    rc, out, _ = run(repo, brain)
    return rc == 0, (rc, out)


def t_unstaged_passes(d):
    brain, repo = setup(d)
    put(repo, "d.md", "clean\n")
    put(repo, "d.md", "clean\nvexmoor\n", stage=False)
    rc, out, _ = run(repo, brain)
    return rc == 0, (rc, out)


def t_longer_word_passes(d):
    brain, repo = setup(d)
    put(repo, "e.md", "the vexmoorian style\n")
    rc, out, _ = run(repo, brain)
    return rc == 0, (rc, out)


def t_no_list_says_so(d):
    _, repo = setup(d)
    put(repo, "f.md", "zorblax quint\n")
    rc, _, err = run(repo, Path(d) / "elsewhere")
    rc2, _, err2 = run(repo)  # neither argument nor BRAIN_DIR
    return rc == 0 and "nothing checked" in err and rc2 == 0 and "nothing checked" in err2, (rc, err, rc2, err2)


if __name__ == "__main__":
    results = [
        case("a staged line with a watched name blocks (case-insensitive)", t_name_blocks),
        case("a staged line with a watched instance name blocks", t_instance_blocks),
        case("negative control: the name only in a removed line passes", t_removed_line_passes),
        case("negative control: an unstaged change is not checked", t_unstaged_passes),
        case("negative control: the name inside a longer word passes", t_longer_word_passes),
        case("no watch list: passes and says nothing was checked", t_no_list_says_so),
    ]
    sys.exit(0 if all(results) else 1)
