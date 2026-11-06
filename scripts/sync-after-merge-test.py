#!/usr/bin/env python3
"""Fixtures for sync-after-merge.py: it removes an untracked copy ONLY where the merged ref holds the same blob.

Real throwaway repos (bare origin + working copy), isolated from the host's git config by git_sandbox. Cases:
identical copies removed (one path with a space stays one path); a differing copy blocks the pull and is kept and
listed, a file the ref lacks is kept and listed (exit 1); all identical: exit 0, pull ok; no repo: exit 2.

    python3 scripts/sync-after-merge-test.py
"""
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import git_sandbox  # noqa: E402,F401  (importing isolates git config)

TOOL = HERE / "sync-after-merge.py"
fails = 0


def run(*args, cwd=None):
    return subprocess.run([str(a) for a in args], cwd=cwd, capture_output=True, text=True)


def git(cwd, *args):
    r = run("git", *args, cwd=cwd)
    assert r.returncode == 0, f"git {args}: {r.stderr}"
    return r.stdout


def check(name, cond, detail=""):
    global fails
    print(("  OK  " if cond else "  FAIL") + f" {name}" + ("" if cond else f" - {detail}"))
    fails += 0 if cond else 1


def setup(root):
    """origin (bare) with an initial commit; `wc` = the operator's working copy; `wt` = where the data PR is made."""
    bare, wt, wc = root / "origin.git", root / "wt", root / "wc"
    git(root, "init", "-q", "--bare", "-b", "main", bare)
    git(root, "clone", "-q", bare, wt)
    (wt / "README").write_text("x\n")
    git(wt, "add", "README")
    git(wt, "commit", "-q", "-m", "init")
    git(wt, "push", "-q", "origin", "HEAD:main")
    git(root, "clone", "-q", bare, wc)
    return wt, wc


def write(base, rel, text):
    p = base / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


def merge_data(wt, files):
    for rel, text in files:
        write(wt, rel, text)
    git(wt, "add", "-A")
    git(wt, "commit", "-q", "-m", "data")
    git(wt, "push", "-q", "origin", "HEAD:main")


with tempfile.TemporaryDirectory() as tmp:
    wt, wc = setup(Path(tmp))
    # The app wrote four files into the operator's copy; three paths went into the merged data PR, one differently.
    for rel, text in (("assets/a.json", "same\n"), ("assets/run 2.json", "same too\n"), ("assets/c.json", "local\n"),
                      ("assets/new.json", "not merged\n")):
        write(wc, rel, text)
    merge_data(wt, (("assets/a.json", "same\n"), ("assets/run 2.json", "same too\n"), ("assets/c.json", "merged\n")))

    r = run(sys.executable, TOOL, wc, "assets")
    out = r.stdout
    check("both identical copies removed, the one with a space as one path", "removed 2 " in out
          and "run 2.json" not in out and not (wc / "assets" / "a.json").exists(), out + r.stderr)
    check("a differing copy blocks the pull, and the tool says so", "pull FAILED" in out, out)
    check("differing copy kept and listed", "KEPT assets/c.json: differs from origin/main" in out
          and (wc / "assets" / "c.json").read_text() == "local\n", out)
    check("file the ref lacks kept and listed", "KEPT assets/new.json: not on origin/main" in out
          and (wc / "assets" / "new.json").exists(), out)
    check("anything kept means exit 1", r.returncode == 1, f"rc={r.returncode}")

with tempfile.TemporaryDirectory() as tmp:
    wt, wc = setup(Path(tmp))
    for rel in ("d/x.txt", "d/run 2.txt"):
        write(wc, rel, "same\n")
    merge_data(wt, (("d/x.txt", "same\n"), ("d/run 2.txt", "same\n")))
    r = run(sys.executable, TOOL, wc)
    check("all identical: exit 0, pull ok, both merged files tracked (one with a space)", r.returncode == 0
          and "pull ok" in r.stdout
          and git(wc, "ls-files", "d").splitlines() == ["d/run 2.txt", "d/x.txt"], r.stdout + r.stderr)

with tempfile.TemporaryDirectory() as tmp:
    r = run(sys.executable, TOOL, Path(tmp) / "no-repo")
    check("not a repo: exit 2", r.returncode == 2, f"rc={r.returncode}")

print("sync-after-merge fixtures:", "ALL passed" if not fails else f"{fails} FAILED")
sys.exit(1 if fails else 0)
