#!/usr/bin/env python3
"""Replace untracked local copies with the merged files - only where the merged branch really carries them, byte-identical.

Why (measured 2026-11-02 on the macOS instance): data an app writes sits untracked in the operator's working copy, goes
into a data PR from a worktree, and after the merge the local copies block `git pull --ff-only`. Removing them by hand,
in the same batch as a merge call that a gate then held, deleted 22 measurement files from the working copy until the
merge went through. This tool decides from the merged ref itself, never from "the merge was sent": a file is removed
only if that ref holds the same path with the same blob.

    sync-after-merge.py <repo> [subdir] [--ref origin/main]

Fetches, removes only untracked files the ref carries identically, then `pull --ff-only`.
Exit 0: nothing left behind and the pull went through. Exit 1: the pull failed, or an untracked file stays because the
ref lacks it or holds it differently (each listed with its reason, never removed). Exit 2: could not run.
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path


def git(repo, *args, check=True):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    if check and r.returncode:
        print(f"sync-after-merge: git {' '.join(args)}: {r.stderr.strip()}", file=sys.stderr)
        sys.exit(2)
    return r


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("repo")
    ap.add_argument("subdir", nargs="?", default=".")
    ap.add_argument("--ref", default="origin/main", help="the merged ref to compare against (default origin/main)")
    a = ap.parse_intermixed_args(argv)
    repo = os.path.abspath(a.repo)
    git(repo, "fetch", "-q", a.ref.split("/", 1)[0])
    # NUL-separated: a path with a space is one path (a plain split() made two of it).
    out = git(repo, "ls-files", "-z", "--others", "--exclude-standard", "--", a.subdir).stdout
    untracked = [p for p in out.split("\0") if p]
    removed, kept = [], []
    for rel in untracked:
        merged = git(repo, "rev-parse", "-q", "--verify", f"{a.ref}:{rel}", check=False).stdout.strip()
        local = git(repo, "hash-object", "--", rel).stdout.strip()
        if merged and merged == local:
            (Path(repo) / rel).unlink()
            removed.append(rel)
        else:
            kept.append((rel, f"not on {a.ref}" if not merged else f"differs from {a.ref}"))
    pull = git(repo, "pull", "--ff-only", "-q", check=False)
    print(f"removed {len(removed)} untracked copies identical on {a.ref}; "
          f"pull {'ok' if not pull.returncode else 'FAILED: ' + pull.stderr.strip()}")
    for rel, why in kept:
        print(f"KEPT {rel}: {why}")
    return 1 if (pull.returncode or kept) else 0


if __name__ == "__main__":
    sys.exit(main())
