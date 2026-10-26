#!/usr/bin/env python3
"""covers: shared-reach-check
Both directions on two synthetic git repos (a brain, a shared memory): a changed private document whose
pointer names a shared file committed later is fine; one whose shared file is OLDER is stale (FAIL); one whose
shared file is missing is stale; a changed document without a pointer is named as unpointed; an excluded path
(ledger, change log) is never listed; a `reach: shared` ledger entry whose id a shared file mentions passes, one
nobody mentions is unexported (FAIL); a closed `- [x]` entry is skipped; --since drops older changes; a missing
shared repo is said and exits 0; instance data adds a marker word. Negative control: with the marker list
emptied every changed document turns unpointed.
Run: scripts/shared-reach-check-test.py    Exit 0 = all green.
"""
from __future__ import annotations
import contextlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("src", ROOT / "scripts" / "shared-reach-check.py")
src = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(src)
fails = 0


def check(cond, name):
    global fails
    print(f"  {'ok  ' if cond else 'FAIL'}  {name}")
    fails += 0 if cond else 1


def git(repo: Path, *args, date: str = ""):
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t",
               GIT_COMMITTER_EMAIL="t@t")
    if date:
        env["GIT_AUTHOR_DATE"] = date
        env["GIT_COMMITTER_DATE"] = date
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, env=env)


def commit(repo: Path, rel: str, text: str, date: str, msg: str = "c"):
    p = repo / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")
    git(repo, "add", rel)
    git(repo, "commit", "-q", "-m", msg, "--", rel, date=date)


def run(brain: Path, shared: Path, *args):
    out = io.StringIO()
    sys.argv = ["shared-reach-check.py", "--repo", str(brain), "--shared", str(shared), *args]
    with contextlib.redirect_stdout(out):
        rc = src.main()
    return rc, out.getvalue()


with tempfile.TemporaryDirectory() as tmp:
    brain = Path(tmp) / "brain"
    shared = Path(tmp) / "shared"
    for r in (brain, shared):
        r.mkdir()
        git(r, "init", "-q")
    rules = brain / ".claude" / "rules"
    rules.mkdir(parents=True)
    (rules / "ledgers.json").write_text(json.dumps({"ledgers": ["docs/net/offene-punkte.md"]}), encoding="utf-8")

    # shared side first (older), then private changes
    commit(shared, "net/segments.md", "# segments\n", "2026-10-20T10:00:00+0000")
    commit(shared, "net/qos.md", "# qos\nmentions export-me-id here\n", "2026-10-26T10:00:00+0000")
    commit(shared, "net/fresh.md", "# fresh\n", "2026-10-26T12:00:00+0000")
    commit(shared, "net/moved.md", "# moved first, pointer minutes later\n", "2026-10-25T08:50:00+0000")

    commit(brain, "docs/net/segments.md",
           "KANONISCH im shared-memory: net/segments.md (seit 2026-10-25)\nlab rest\n", "2026-10-25T09:00:00+0000")
    commit(brain, "docs/net/fresh.md",
           "CANONICAL in shared memory: net/fresh.md\nlab rest\n", "2026-10-25T09:00:00+0000")
    commit(brain, "docs/net/moved.md",
           "CANONICAL in shared memory: net/moved.md\nlab rest\n", "2026-10-25T09:00:00+0000")
    commit(brain, "docs/net/missing.md",
           "CANONICAL in shared memory: net/not-there.md\n", "2026-10-25T09:00:00+0000")
    commit(brain, "docs/net/nopointer.md", "# plan\nsomething generic\n", "2026-10-25T09:00:00+0000")
    commit(brain, "docs/net/change-log.md", "# log\n", "2026-10-25T09:00:00+0000")
    # committed AFTER the younger ones but dated before the window: `git log --since` would stop
    # here and hide everything above — the check filters per commit date instead
    commit(brain, "docs/net/old.md", "# old, before the window\n", "2026-10-01T09:00:00+0000")
    commit(brain, "docs/net/offene-punkte.md",
           "# ledger\n- [ ] **exported** · id: export-me-id · reach: shared\n"
           "- [ ] **not exported** · id: never-exported-id · reach: shared\n"
           "- [x] **closed** · id: closed-id · reach: shared\n"
           "- [ ] **brain only** · id: brain-only-id · reach: brain\n", "2026-10-25T09:00:00+0000")

    print("instance marker from shared-reach.json")
    (rules / "shared-reach.json").write_text(json.dumps({"markers": ["CANONICAL in shared memory:", "KANONISCH im shared-memory:"]}), encoding="utf-8")
    rc, out = run(brain, shared, "--since", "2026-10-24")
    check(rc == 0, "exit 0")
    check("FAIL shared-reach: docs/net/segments.md points to net/segments.md — shared 2026-10-20 older than private 2026-10-25" in out, "stale: shared older than private is a FAIL")
    check("docs/net/missing.md points to net/not-there.md — shared file missing" in out, "stale: missing shared file is a FAIL")
    check("docs/net/fresh.md" not in out, "fresh: shared newer than private is silent")
    check("docs/net/moved.md" not in out, "grace: private pointer minutes after the shared file is silent")
    check("docs/net/nopointer.md changed privately, no shared counterpart" in out, "unpointed document is named with the question")
    check("change-log" not in out, "excluded path never listed")
    check("docs/net/old.md" not in out, "--since drops a change before the window")
    check("entry `never-exported-id` is reach: shared but no shared file names it" in out, "unexported reach: shared entry is a FAIL")
    check("export-me-id" not in out, "exported entry (a shared file names its id) is silent")
    check("closed-id" not in out, "closed entry is skipped")
    check("brain-only-id" not in out, "reach: brain entry is not a shared entry")
    check("shared-reach summary: changed=5 pointed=4 stale=2 unpointed=1 shared_entries=2 unexported=1" in out, f"summary line: {out.strip().splitlines()[-1]}")

    print("json form")
    rc, out = run(brain, shared, "--since", "2026-10-24", "--json")
    data = json.loads(out)
    check(data["changed"] == 5 and len(data["stale"]) == 2 and data["unpointed"] == ["docs/net/nopointer.md"], "json carries the same counts")

    print("negative control: marker list emptied")
    (rules / "shared-reach.json").write_text(json.dumps({"markers": []}), encoding="utf-8")
    rc, out = run(brain, shared, "--since", "2026-10-24")
    check("pointed=0 stale=0 unpointed=5" in out, "without markers every changed document is unpointed")
    (rules / "shared-reach.json").unlink()

    print("default marker only (no instance data): the German pointer is not read")
    rc, out = run(brain, shared, "--since", "2026-10-24")
    check("docs/net/segments.md changed privately, no shared counterpart" in out, "German marker needs the instance word")

    print("missing shared repo")
    rc, out = run(brain, Path(tmp) / "nowhere", "--since", "2026-10-24")
    check(rc == 0 and "NOT checked" in out, "a missing shared repo is said, exit 0")

print("shared-reach-check-test: " + ("all checks passed" if fails == 0 else f"{fails} check(s) FAILED"))
sys.exit(1 if fails else 0)
